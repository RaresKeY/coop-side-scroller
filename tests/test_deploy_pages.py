"""Offline deployment contracts: no GitHub writes or browser/network required."""
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('deploy_pages', Path(__file__).resolve().parents[1] / 'tools/deploy_pages.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentTests(unittest.TestCase):
    def test_failed_build_is_not_success(self):
        with patch.object(deploy, 'api', return_value=[{'commit': 'abc', 'status': 'errored'}]):
            with self.assertRaisesRegex(RuntimeError, 'errored'):
                deploy.wait_for_pages('abc', 1)

    def test_wrong_commit_never_counts_as_success(self):
        with patch.object(deploy, 'api', return_value=[{'commit': 'other', 'status': 'built'}]), \
             patch.object(deploy.time, 'monotonic', side_effect=[0, 0, 1, 2]), \
             patch.object(deploy.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'not verified'):
                deploy.wait_for_pages('abc', 1)

    def test_transient_api_error_then_exact_success(self):
        with patch.object(deploy, 'api', side_effect=[subprocess.CalledProcessError(1, 'gh'), [{'commit': 'abc', 'status': 'built'}]]), \
             patch.object(deploy.time, 'sleep'):
            deploy.wait_for_pages('abc', 1)

    def test_hosted_mismatch_fails(self):
        with patch.object(deploy.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong')), \
             patch.object(deploy.time, 'monotonic', side_effect=[0, 0, 0, 0, 1, 2]), \
             patch.object(deploy.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'index.html'):
                deploy.verify_hosted('abc', {'index.html': 'wrong-hash'}, 1)

    def test_all_hosted_hashes_checked(self):
        expected = {name: deploy.hashlib.sha256(name.encode()).hexdigest() for name in ['index.pck', 'index.html']}
        with patch.object(deploy.urllib.request, 'urlopen', side_effect=[io.BytesIO(name.encode()) for name in expected]):
            deploy.verify_hosted('abc', expected, 1)

    def test_candidate_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(deploy, 'SITE', Path(tmp)):
            for name in deploy.REQUIRED:
                (Path(tmp) / name).write_text('candidate')
            (Path(tmp) / 'leak.txt').symlink_to(Path(tmp) / 'index.html')
            with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
                deploy.candidate_hashes()

    def test_publication_lock_excludes_second_owner(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(deploy, 'common_dir', return_value=Path(tmp)):
            with deploy.publication_lock():
                with self.assertRaisesRegex(RuntimeError, 'lock busy'):
                    with deploy.publication_lock(timeout=0):
                        self.fail('second lock acquired')

    def test_real_git_publication_preserves_checkout_and_rejects_remote_race(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            remote, root = base / 'remote.git', base / 'source'
            def run(*args):
                return subprocess.check_output(['git', *map(str, args)], stderr=subprocess.DEVNULL, text=True).strip()
            run('init', '--bare', remote)
            run('init', root)
            run('-C', root, 'config', 'user.name', 'Test')
            run('-C', root, 'config', 'user.email', 'test@example.invalid')
            run('-C', root, 'remote', 'add', 'origin', remote)
            (root / 'source').write_text('source')
            run('-C', root, 'add', 'source')
            run('-C', root, 'commit', '-m', 'source')
            original = run('-C', root, 'rev-parse', 'HEAD')
            original_index = run('-C', root, 'ls-files', '--stage')
            (root / 'source').write_text('dirty work')
            site = root / 'build/web'
            site.mkdir(parents=True)
            (site / 'index.html').write_text('candidate')
            with patch.object(deploy, 'ROOT', root), patch.object(deploy, 'SITE', site):
                commit = deploy.publish()
                self.assertEqual(run('--git-dir', remote, 'rev-parse', deploy.REF), commit)
                self.assertEqual(run('-C', root, 'rev-parse', 'HEAD'), original)
                self.assertEqual((root / 'source').read_text(), 'dirty work')
                self.assertEqual(run('-C', root, 'ls-files', '--stage'), original_index)
                self.assertEqual(deploy.publish(), commit)  # No duplicate build.
                (site / 'index.html').write_text('next candidate')
                real_git = deploy.git
                def raced_git(*args, **kwargs):
                    if args[0] == 'push':
                        tree = real_git('rev-parse', commit + '^{tree}')
                        other = real_git('commit-tree', tree, '-p', commit, input='Other deploy\n')
                        run('--git-dir', remote, 'update-ref', deploy.REF, other)
                    return real_git(*args, **kwargs)
                with patch.object(deploy, 'git', side_effect=raced_git):
                    with self.assertRaises(subprocess.CalledProcessError):
                        deploy.publish()
                self.assertEqual(run('-C', root, 'rev-parse', 'HEAD'), original)
                self.assertEqual(run('-C', root, 'ls-files', '--stage'), original_index)


if __name__ == '__main__':
    unittest.main()
