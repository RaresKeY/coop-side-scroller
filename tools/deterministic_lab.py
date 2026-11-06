#!/usr/bin/env python3
"""Bounded, reproducible two-core experiment; no service calls or credentials.

Packet impairment is simulated here, not evidence of internet connectivity.
Run tests/deterministic.sh to prepare and verify native/Wasm parity as well.
"""
import argparse
import ctypes as C
import heapq
import json
from pathlib import Path
import random
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ('struct_size tick confirmed_tick state_hash peer_ack stalls rollbacks '
          'resimulated_ticks rejected desync max_correction dropped_events '
          'local_through remote_through').split()


class Stats(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in FIELDS]


class Event(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in ('tick', 'type', 'slot', 'value')]


def library(path):
    api = C.CDLL(str(path))
    signatures = {
        'create': ([C.c_uint32, C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32], C.c_void_p),
        'destroy': ([C.c_void_p], None),
        'input': ([C.c_void_p, C.c_uint32, C.c_int32, C.c_uint32], C.c_int32),
        'advance': ([C.c_void_p, C.c_uint32], C.c_int32),
        'stats': ([C.c_void_p, C.c_void_p, C.c_uint32], C.c_int32),
        'next_event': ([C.c_void_p, C.c_void_p], C.c_int32),
        'pack': ([C.c_void_p, C.c_uint32, C.c_uint32, C.c_void_p, C.c_uint32], C.c_int32),
        'receive': ([C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32], C.c_int32),
        'save': ([C.c_void_p, C.c_void_p, C.c_uint32], C.c_int32),
        'load': ([C.c_void_p, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32], C.c_int32),
    }
    for name, (args, result) in signatures.items():
        fn = getattr(api, 'ec_v1_deterministic_' + name)
        fn.argtypes, fn.restype = args, result
        setattr(api, name, fn)
    return api


class Peer:
    def __init__(self, api, slot, prediction):
        self.api, self.slot = api, slot
        self.handle = api.create(0x10000, slot, bytes(range(1, 17)), 0, prediction)
        if not self.handle:
            raise RuntimeError('Cannot allocate deterministic core')
        self.events = []

    def close(self):
        if self.handle:
            self.api.destroy(self.handle)
            self.handle = None

    def stats(self):
        result = Stats()
        assert self.api.stats(self.handle, C.byref(result), C.sizeof(result)) == 0
        return result

    def input(self, tick, value):
        return self.api.input(self.handle, tick, *value)

    def advance(self, target):
        result = self.api.advance(self.handle, target)
        assert result in (0, 1), ('advance', result, target)
        event = Event()
        while self.api.next_event(self.handle, C.byref(event)) == 0:
            self.events.append(tuple(getattr(event, field) for field in ('tick', 'type', 'slot', 'value')))
        return self.stats()

    def pack(self, first, count):
        output = C.create_string_buffer(80)
        size = self.api.pack(self.handle, first, count, output, 80)
        assert size >= 48, ('pack', first, count, size)
        return output.raw[:size]

    def receive(self, sender, payload):
        result = self.api.receive(self.handle, sender, payload, len(payload))
        assert result in (0, -5), ('receive', result, sender)

    def save(self):
        output = C.create_string_buffer(140)
        assert self.api.save(self.handle, output, 140) == 140
        return output.raw

    def load(self, checkpoint, epoch, mask=3):
        assert self.api.load(self.handle, checkpoint, len(checkpoint), epoch, mask) == 0


def controls(tick, slot, seed=1):
    # Integer-only adversarial traces include small analog axes and held edges.
    value = (tick * 1103515245 + slot * 12345 + seed * 2654435761) & 0xffffffff
    phase = (tick // 73 + seed + slot) % 6
    axis = (1000, -1000, 333, -499, 0, 1000)[phase]
    if tick < 170:
        axis = 1000
    flags = (1 if tick % 47 < 7 else 0) | (2 if value & 8 else 0)
    return axis, flags


def trace(api, ticks, seed=1):
    peers = [Peer(api, 1, 0), Peer(api, 2, 12)]
    hashes = []
    checkpoints = []
    try:
        for tick in range(1, ticks + 1):
            for p in peers:
                assert p.input(tick, controls(tick, p.slot, seed)) == 0
            for p in peers:
                peers[2 - p.slot].receive(p.slot, p.pack(tick, 1))
            stats = [p.advance(tick) for p in peers]
            assert stats[0].state_hash == stats[1].state_hash
            hashes.append(stats[0].state_hash)
            if tick % 997 == 0:
                checkpoints.append(list(peers[0].save()))
        assert peers[0].events == peers[1].events
        assert len(set(peers[0].events)) == len(peers[0].events)
        assert peers[0].save() == peers[1].save()
        return {'ticks': ticks, 'seed': seed, 'hashes': hashes,
                'checkpoints': checkpoints, 'events': [list(e) for e in peers[0].events],
                'final': list(peers[0].save())}
    finally:
        for p in peers:
            p.close()


def scenario(api, *, name, ticks, prediction, delay=0, transit=0, jitter=0,
             loss=0, blackout=None, seed=42, batch=2):
    peers = [Peer(api, 1, prediction), Peer(api, 2, prediction)]
    rng, pending = random.Random(seed), []
    sequence = bytes_sent = packets_sent = dropped = 0
    latest_sent = [0, 0]
    max_behind = 0
    start = time.perf_counter()

    def send(p, first, count, wall):
        nonlocal sequence, bytes_sent, packets_sent, dropped
        packet = p.pack(first, count)
        packets_sent += 1
        bytes_sent += len(packet)
        if rng.random() < loss:
            dropped += 1
            return
        sequence += 1
        due = wall + transit + rng.randint(0, jitter)
        destination = 2 - p.slot
        if blackout and destination == 1 and blackout[0] <= due <= blackout[1]:
            due = blackout[1] + 1
        heapq.heappush(pending, (due, sequence, destination, packet))

    try:
        for wall in range(1, ticks + 3000):
            for index, p in enumerate(peers):
                if blackout and index == 1 and blackout[0] <= wall <= blackout[1]:
                    continue
                stats = p.stats()
                # At most four input frames captured after a suspended browser.
                wanted = min(ticks, wall + delay, stats.confirmed_tick + 120)
                for tick in range(stats.local_through + 1, min(wanted, stats.local_through + 4) + 1):
                    value = controls(tick - delay, p.slot) if tick > delay else (0, 0)
                    assert p.input(tick, value) == 0
                stats = p.advance(min(wall, ticks))
                max_behind = max(max_behind, min(wall, ticks) - stats.tick)
                if wall % batch == 0:
                    count = min(8, stats.local_through - latest_sent[index])
                    send(p, latest_sent[index] + 1 if count else 0, count, wall)
                    latest_sent[index] += count
                if wall % 12 == 0 and stats.peer_ack < stats.local_through:
                    send(p, stats.peer_ack + 1, min(8, stats.local_through - stats.peer_ack), wall)
            while pending and pending[0][0] <= wall:
                _, _, destination, packet = heapq.heappop(pending)
                peers[destination].receive(2 - destination, packet)
            if all(p.stats().confirmed_tick == ticks for p in peers):
                break
        else:
            raise AssertionError((name, 'did not recover', [p.stats().confirmed_tick for p in peers]))
        assert peers[0].save() == peers[1].save(), (name, 'checkpoint divergence')
        assert peers[0].events == peers[1].events, (name, 'event divergence')
        assert len(set(peers[0].events)) == len(peers[0].events), (name, 'duplicate side effects')
        # An independent, impairment-free pair is the oracle, not just two peers
        # agreeing on a potentially incomplete sequence of inputs.
        reference = [Peer(api, 1, 0), Peer(api, 2, 0)]
        try:
            for tick in range(1, ticks + 1):
                for p in reference:
                    assert p.input(tick, controls(tick - delay, p.slot) if tick > delay else (0, 0)) == 0
                for p in reference:
                    reference[2 - p.slot].receive(p.slot, p.pack(tick, 1))
                for p in reference:
                    p.advance(tick)
            assert reference[0].save() == peers[0].save(), (name, 'oracle divergence')
            assert reference[0].events == peers[0].events
        finally:
            for p in reference:
                p.close()
        stats = [p.stats() for p in peers]
        return {'name': name, 'ticks': ticks, 'seed': seed,
                'batch_interval_frames': batch,
                'prediction_frames': prediction, 'input_delay_ms': round(delay * 1000 / 60, 2),
                'one_way_delay_ms': round(transit * 1000 / 60, 2),
                'jitter_ms': round(jitter * 1000 / 60, 2), 'loss_fraction': loss,
                'suspended_frames': list(blackout) if blackout else None,
                'converged_at_wall_tick': wall, 'max_behind_ms': round(max_behind * 1000 / 60, 2),
                'rollbacks': sum(s.rollbacks for s in stats),
                'speculative_ticks_executed': sum(s.resimulated_ticks for s in stats),
                'max_correction_reference_pixels': max(s.max_correction for s in stats) / 1000,
                'encoded_bytes': bytes_sent, 'packets': packets_sent, 'dropped_packets': dropped,
                'encoded_bytes_per_second': round(bytes_sent / (wall / 60), 2),
                'events_per_peer': len(peers[0].events), 'state_hash': stats[0].state_hash,
                'dropped_events': sum(s.dropped_events for s in stats),
                'lab_wall_seconds_including_oracle': round(time.perf_counter() - start, 4)}
    finally:
        for p in peers:
            p.close()


def recovery(api):
    a, b = Peer(api, 1, 12), Peer(api, 2, 12)
    try:
        for t in range(1, 95):
            for p in (a, b):
                assert p.input(t, controls(t, p.slot)) == 0
            a.receive(2, b.pack(t, 1)); b.receive(1, a.pack(t, 1))
            a.advance(t); b.advance(t)
        checkpoint = a.save()
        old_packet = a.pack(94, 1)
        # Model reload with a genuinely new handle, not merely a reused view.
        b.close(); b = Peer(api, 2, 12)
        for p in (a, b):
            p.load(checkpoint, 1)
        assert b.api.receive(b.handle, 1, old_packet, len(old_packet)) == -4
        for t in range(95, 125):
            for p in (a, b):
                assert p.input(t, controls(t, p.slot)) == 0
            a.receive(2, b.pack(t, 1)); b.receive(1, a.pack(t, 1))
            a.advance(t); b.advance(t)
        assert a.save() == b.save()
        checkpoint = b.save(); a.close()
        b.load(checkpoint, 2, 2)
        for t in range(125, 485):
            assert b.input(t, controls(t, 2)) == 0
            b.advance(t)
        solo_tick = b.stats().confirmed_tick
        # Retained local/optional cloud bytes can reconstruct after BOTH close.
        checkpoint = b.save(); b.close(); b = Peer(api, 2, 12)
        b.load(checkpoint, 3, 2)
        assert b.stats().confirmed_tick == solo_tick
        return {'checkpoint_bytes': len(checkpoint), 'reload_rejoin_tick': 124,
                'creator_departure_solo_tick': solo_tick,
                'both_closed_restore_tick': b.stats().confirmed_tick,
                'old_epoch_rejected': True, 'cloud_storage_used': False,
                'boundary': 'Explicit trusted checkpoint barriers; no live ICE restart or automatic membership negotiation'}
    finally:
        a.close(); b.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=ROOT / 'build/native/libember_core.so')
    parser.add_argument('--ticks', type=int, default=6000)
    parser.add_argument('--trace-only', action='store_true')
    args = parser.parse_args()
    if not 1000 <= args.ticks <= 100000:
        parser.error('--ticks must be between 1000 and 100000')
    if args.library.resolve() == ROOT / 'build/native/libember_core.so':
        subprocess.run([sys.executable, str(ROOT / 'tools/build_core.py'), '--check'], check=True)
    api = library(args.library.resolve())
    traces = [trace(api, args.ticks, seed) for seed in (1, 7, 123)]
    output = ROOT / 'build/deterministic'
    output.mkdir(parents=True, exist_ok=True)
    (output / ('clang-traces.json' if args.trace_only else 'native-traces.json')).write_text(json.dumps(traces) + '\n')
    if args.trace_only:
        expected = json.loads((output / 'native-traces.json').read_text())
        assert traces == expected, 'GCC/Clang traces differ'
        print('GCC/Clang deterministic traces PASS:', args.ticks * len(traces), 'ticks')
        return
    scenarios = []
    for batch in (2, 4):
        for mode, prediction, delay in [('lockstep', 0, 6), ('rollback', 12, 0)]:
            for network, options in [
                ('clean', {}),
                ('wan', {'transit': 3, 'jitter': 2, 'loss': .05}),
                ('suspension', {'transit': 3, 'jitter': 2, 'loss': .05, 'blackout': (180, 300)}),
            ]:
                scenarios.append(scenario(api, name=f'{mode}-{network}-batch{batch}', ticks=1800,
                                          prediction=prediction, delay=delay, batch=batch, **options))
    report = {'schema': 1, 'evidence': 'Native C ABI with simulated transport impairment',
              'trace_ticks': args.ticks * len(traces), 'scenarios': scenarios,
              'recovery': recovery(api)}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Deterministic native traces PASS:', report['trace_ticks'], 'ticks')
    for case in scenarios:
        print(case['name'], 'PASS', case['encoded_bytes_per_second'], 'encoded B/s;',
              case['rollbacks'], 'corrections;', case['max_behind_ms'], 'ms max behind')
    print('Checkpoint/reload/creator departure/epoch fencing PASS:', report['recovery'])


if __name__ == '__main__':
    main()
