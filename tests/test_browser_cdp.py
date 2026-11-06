"""CDP budgets must cover fragmented frames and bounded asynchronous page work."""
import json
import socket
import threading
import time
import unittest

from browser_cdp import CDP


class DeadlineTests(unittest.TestCase):
    def peer(self):
        client, server = socket.socketpair()
        self.addCleanup(client.close)
        self.addCleanup(server.close)
        cdp = CDP.__new__(CDP)
        cdp.socket, cdp.sequence, cdp.errors = client, 0, []
        client.settimeout(.01)
        return cdp, server

    def test_response_outlives_old_socket_timeout_and_keeps_fragments(self):
        cdp, server = self.peer()

        def respond():
            server.recv(4096)
            raw = json.dumps({'id': 1, 'result': {'ok': True}}).encode()
            frame = bytes([0x81, len(raw)]) + raw
            server.sendall(frame[:1])
            time.sleep(.05)
            server.sendall(frame[1:3])
            time.sleep(.05)
            server.sendall(frame[3:])

        thread = threading.Thread(target=respond)
        thread.start()
        try:
            self.assertEqual(cdp.call('fixture', timeout=1), {'ok': True})
        finally:
            thread.join(timeout=2)

    def test_partial_frame_cannot_extend_total_deadline(self):
        cdp, server = self.peer()

        def respond():
            server.recv(4096)
            server.sendall(b'\x81')
            time.sleep(.4)

        thread = threading.Thread(target=respond)
        thread.start()
        begin = time.monotonic()
        try:
            with self.assertRaises(TimeoutError):
                cdp.call('fixture', timeout=.1)
            self.assertLess(time.monotonic() - begin, .35)
        finally:
            thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
