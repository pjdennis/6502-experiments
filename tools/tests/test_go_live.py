"""Tests for tools/reorg/go_live.sh against a throwaway local 'origin'."""
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'reorg', 'go_live.sh'))


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class GoLiveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.remote = os.path.join(self.tmp, 'remote.git')
        work = os.path.join(self.tmp, 'seed')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'main', self.remote)
        git(self.tmp, 'init', '-q', '-b', 'main', work)
        for k, v in (('user.email', 't@example.com'), ('user.name', 'T')):
            git(work, 'config', k, v)
        def commit(msg):
            with open(os.path.join(work, 'f'), 'a') as f:
                f.write(msg + '\n')
            git(work, 'add', 'f'); git(work, 'commit', '-q', '-m', msg)
            return git(work, 'rev-parse', 'HEAD')
        self.first = commit('first')                      # main
        git(work, 'branch', 'old-feature')                # fully merged
        commit('trial work')
        git(work, 'checkout', '-q', '-b', 'unmerged', self.first)
        commit('unmerged work')                           # not in trial
        git(work, 'checkout', '-q', 'main')
        git(work, 'checkout', '-q', '-b', 'trial')
        git(work, 'reset', '-q', '--hard', 'main')
        git(work, 'merge', '-q', '--ff-only', 'main')
        git(work, 'checkout', '-q', 'main'); git(work, 'reset', '-q', '--hard', self.first)
        git(work, 'checkout', '-q', 'trial'); commit('more trial work')
        self.trial = git(work, 'rev-parse', 'HEAD')
        git(work, 'push', '-q', self.remote, 'main', 'old-feature', 'unmerged', 'trial')
        self.clone = os.path.join(self.tmp, 'clone')
        git(self.tmp, 'clone', '-q', self.remote, self.clone)
        self.milestones = os.path.join(self.tmp, 'milestones.txt')
        with open(self.milestones, 'w') as f:
            f.write(f'# tag commit message\nm/first {self.first} The first commit\n')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_script(self, *args):
        env = dict(os.environ, TRIAL_BRANCH='trial', MILESTONES=self.milestones,
                   REORG_BEFORE=self.first)
        return subprocess.run(['bash', SCRIPT, *args], cwd=self.clone, env=env,
                              capture_output=True, text=True)

    def remote_refs(self):
        return git(self.remote, 'for-each-ref', '--format=%(refname) %(objectname)')

    def test_dry_run_changes_nothing_and_prints_plan(self):
        before = self.remote_refs()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_refs(), before)
        self.assertIn('DRY RUN', result.stdout)
        self.assertIn('archive/unmerged', result.stdout)
        self.assertIn('refs/heads/main', result.stdout)

    def test_apply_fast_forwards_main_tags_and_prunes(self):
        result = self.run_script('--apply')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        refs = self.remote_refs()
        self.assertIn(f'refs/heads/main {self.trial}', refs)
        self.assertIn('refs/heads/trial', refs)                 # trial branch kept
        self.assertNotIn('refs/heads/old-feature', refs)        # merged -> deleted
        self.assertNotIn('refs/heads/unmerged', refs)           # archived -> deleted
        for tag in ('archive/old-feature', 'archive/unmerged', 'archive/main',
                    'm/first', 'reorg/before', 'reorg/after'):
            self.assertIn(f'refs/tags/{tag} ', refs)
        # the unmerged work is still reachable through its archive tag
        self.assertEqual(git(self.remote, 'rev-parse', 'archive/unmerged^{commit}'),
                         git(self.remote, 'rev-parse', 'archive/unmerged^{commit}'))

    def test_refuses_when_main_is_not_an_ancestor_of_trial(self):
        other = os.path.join(self.tmp, 'other')
        git(self.tmp, 'clone', '-q', self.remote, other)
        for k, v in (('user.email', 't@example.com'), ('user.name', 'T')):
            git(other, 'config', k, v)
        with open(os.path.join(other, 'g'), 'w') as f:
            f.write('diverged\n')
        git(other, 'add', 'g'); git(other, 'commit', '-q', '-m', 'diverge main')
        git(other, 'push', '-q', 'origin', 'main')
        before = self.remote_refs()
        result = self.run_script('--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not an ancestor', result.stdout + result.stderr)
        self.assertEqual(self.remote_refs(), before)


if __name__ == '__main__':
    unittest.main()
