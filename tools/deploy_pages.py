#!/usr/bin/env python3
"""Publish a prepared candidate and verify its exact Pages deployment."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'build/web'
DESTINATION = 'https://github.com/RaresKeY/coop-side-scroller.git'
REPOSITORY = 'RaresKeY/coop-side-scroller'
URL = 'https://rareskey.github.io/coop-side-scroller/'
REF = 'refs/heads/gh-pages'
REQUIRED = {'index.html', 'index.js', 'index.pck', 'index.wasm', 'ember_core.wasm',
            'ember_core_bridge.js', 'build-info.json', '.nojekyll', 'THIRD_PARTY_NOTICES.txt'}

OPTIONAL = {'index.png', 'index.icon.png', 'index.apple-touch-icon.png',
            'index.audio.worklet.js', 'index.audio.position.worklet.js'}


def git(*args, **kwargs):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True,
                                   timeout=120, **kwargs).strip()


def common_dir():
    path = Path(git('rev-parse', '--git-common-dir'))
    return path if path.is_absolute() else ROOT / path


@contextlib.contextmanager
def publication_lock(timeout=1200):
    # Build and deployment share this lock, including across Git worktrees.
    with (common_dir() / 'web-publication.lock').open('a') as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Build/deployment lock busy; no publication performed')
                time.sleep(1)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def candidate_hashes():
    files = list(SITE.iterdir())
    if any(p.is_symlink() or not p.is_file() or
           p.name not in REQUIRED | OPTIONAL for p in files):
        raise RuntimeError('Unexpected candidate content')
    if not REQUIRED.issubset({p.name for p in files}):
        raise RuntimeError('Incomplete candidate; run tools/build_web.sh')
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def publish():
    # Fetch the actual published tip, never a possibly stale local Pages branch.
    rows = git('ls-remote', 'origin', REF).splitlines()
    parent = rows[0].split()[0] if rows else ''
    if parent:
        # Fetch the immutable parent without touching another agent's FETCH_HEAD.
        git('fetch', '--no-tags', '--no-write-fetch-head', 'origin', parent)
    with tempfile.TemporaryDirectory(prefix='ember-pages-index-') as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / 'index'))
        prefix = ['git', '--git-dir', git('rev-parse', '--absolute-git-dir'),
                  '--work-tree', str(SITE)]
        for args in [('read-tree', '--empty'), ('add', '--all', '.')]:
            subprocess.run([*prefix, *args], cwd=SITE, env=env, check=True, timeout=120)
        tree = subprocess.check_output([*prefix, 'write-tree'], env=env,
                                       text=True, timeout=120).strip()
        if parent and git('rev-parse', parent + '^{tree}') == tree:
            print('Candidate already pushed; verifying existing commit', parent, flush=True)
            return parent
        args = ['commit-tree', tree]
        if parent:
            args += ['-p', parent]
        commit = git(*args, input='Deploy current Godot Web prototype\n')
        # Push the immutable object, not a shared mutable local branch name.
        # The lease rejects concurrent remote changes, including branch creation.
        git('push', f'--force-with-lease={REF}:{parent}', 'origin', f'{commit}:{REF}')
        # Do not mutate the shared local gh-pages branch at all.
        return commit


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True, timeout=30))


def wait_for_pages(commit, timeout):
    deadline = time.monotonic() + timeout
    last = 'not yet registered'
    while time.monotonic() < deadline:
        try:
            builds = api(f'repos/{REPOSITORY}/pages/builds?per_page=100')
            build = next((b for b in builds if b['commit'] == commit), None)
            if build:
                last = build['status']
                if last == 'built':
                    return
                if last in {'errored', 'cancelled'}:
                    raise RuntimeError(f'Pages deployment {commit} {last}; inspect https://github.com/{REPOSITORY}/actions')
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            last = f'GitHub status temporarily unavailable ({type(error).__name__})'
        print(f'Pages {commit[:7]}: {last}', flush=True)
        time.sleep(min(10, max(0, deadline - time.monotonic())))
    raise RuntimeError(f'Pages {commit} not verified after {timeout}s ({last}); pushed commit remains intact')


def verify_hosted(commit, expected, timeout):
    deadline = time.monotonic() + timeout
    pending = dict(expected)
    while pending and time.monotonic() < deadline:
        for name, digest in list(pending.items()):
            if time.monotonic() >= deadline:
                break
            request = urllib.request.Request(URL + name + '?commit=' + commit,
                                             headers={'Cache-Control': 'no-cache'})
            try:
                with urllib.request.urlopen(request, timeout=min(30, max(0.1, deadline - time.monotonic()))) as response:
                    # Stream large engine/PCK files instead of retaining copies.
                    actual = hashlib.file_digest(response, 'sha256').hexdigest()
                if actual == digest:
                    del pending[name]
            except (urllib.error.URLError, TimeoutError):
                pass
        if pending:
            time.sleep(min(5, max(0, deadline - time.monotonic())))
    if pending:
        raise RuntimeError('Hosted files not verified: ' + ', '.join(sorted(pending)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=900, help='Pages wait deadline in seconds')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    with publication_lock():
        if git('remote', 'get-url', '--push', 'origin') != DESTINATION:
            raise RuntimeError('Origin does not match the configured GitHub project')
        # Fail before pushing if monitoring is unavailable or the Pages target differs.
        pages = api(f'repos/{REPOSITORY}/pages')
        if pages.get('build_type') != 'legacy' or pages.get('source') != {'branch': 'gh-pages', 'path': '/'}:
            raise RuntimeError('Unexpected Pages configuration')
        expected = candidate_hashes()
        subprocess.run([sys.executable, str(ROOT / 'tools/audit_publication.py')],
                       check=True, cwd=ROOT)
        commit = publish()
        wait_for_pages(commit, args.timeout)
        verify_hosted(commit, expected, min(args.timeout, 180))
        print(f'Pages {commit} built; all hosted candidate hashes verified. Run hosted browser checks before cleanup.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
