import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

SENTINEL = Path(__file__).with_name('pr-sentinel.py')
REPO = 'owner/repo'
PULL = f'repos/{REPO}/pulls/1'
REVIEWS = f'{PULL}/reviews?per_page=100'
ISSUE_COMMENTS = f'repos/{REPO}/issues/1/comments?per_page=100'
REVIEW_COMMENTS = f'{PULL}/comments?per_page=100'
CHECKS = f'repos/{REPO}/commits/new-head/check-runs?per_page=100'
STATUS = f'repos/{REPO}/commits/new-head/status'

FAKE_API = '''\
import json
import sys
from pathlib import Path

if sys.argv[1] == 'api':
    _, endpoint = sys.argv[1:]
else:
    _, repo, endpoint = sys.argv[1:]
    assert endpoint.startswith(f'repos/{repo}/'), sys.argv
responses = json.loads(Path(__file__).with_name('responses.json').read_text())
if endpoint not in responses and '&page=' in endpoint:
    print('[]')
    sys.exit(0)
result = responses[endpoint]
if isinstance(result, dict) and '$error' in result:
    sys.exit(result['$error'])
print(result if isinstance(result, str) else json.dumps(result))
'''


def review(state, head='new-head', login='reviewer'):
    return {'state': state, 'commit_id': head, 'user': {'login': login}}


class SentinelTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        script = self.root / 'fake api.py'
        script.write_text(f'#!{sys.executable}\n{FAKE_API}')
        script.chmod(0o700)
        (self.root / 'gh').symlink_to(script)
        self.api = shlex.join([sys.executable, str(script), '--repo', '{repo}', '{endpoint}'])
        self.registry = [{'repo': REPO, 'number': 1}]
        self.responses = {
            PULL: {'state': 'open', 'draft': False, 'merged': False, 'head': {'sha': 'new-head'}},
            REVIEWS: [],
            ISSUE_COMMENTS: [],
            REVIEW_COMMENTS: [],
            CHECKS: {'total_count': 1, 'check_runs': [{'name': 'unit', 'conclusion': 'success'}]},
            STATUS: {'state': 'pending', 'total_count': 0, 'statuses': []},
        }
        self.snapshot = self.root / 'snapshot.json'

    def run_sentinel(self, mode, *args, default_api=False):
        registry = self.root / 'registry.json'
        registry.write_text(json.dumps(self.registry))
        (self.root / 'responses.json').write_text(json.dumps(self.responses))
        cmd = [sys.executable, '-B', str(SENTINEL), mode, str(registry), str(self.snapshot), *args]
        if not default_api:
            cmd.extend(['--api', self.api])
        env = dict(os.environ, PATH=f'{self.root}{os.pathsep}{os.environ.get("PATH", "")}')
        return subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env)

    def save(self, *args, default_api=False):
        result = self.run_sentinel('snapshot', *args, default_api=default_api)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(self.snapshot.read_text())

    def check(self, expected, *, default_api=False):
        result = self.run_sentinel('check', default_api=default_api)
        self.assertEqual(result.returncode, expected, result.stderr or result.stdout)
        return result.stdout

    def test_unchanged_through_default_api(self):
        snap = self.save(default_api=True)
        self.assertEqual(snap[f'{REPO}#1']['checks'], 'pass')
        self.assertEqual(self.check(1, default_api=True).strip(), 'no material change')

    def test_changes_requested_for_current_head(self):
        self.save()
        self.responses[REVIEWS] = [review('APPROVED', login='other'), review('CHANGES_REQUESTED')]
        self.assertIn(f"{REPO}#1: review '' -> 'CHANGES_REQUESTED'", self.check(0))

    def test_review_on_old_head_does_not_count(self):
        self.save()
        self.responses[REVIEWS] = [review('CHANGES_REQUESTED', head='old-head')]
        out = self.check(0)
        self.assertIn('reviews 0 -> 1', out)
        self.assertNotIn('review ', out.replace('reviews ', ''))

    def test_latest_decision_and_dismissal(self):
        self.responses[REVIEWS] = [review('CHANGES_REQUESTED'), review('APPROVED'), review('COMMENTED')]
        self.assertEqual(self.save()[f'{REPO}#1']['review'], 'APPROVED')
        self.responses[REVIEWS].append(review('DISMISSED'))
        self.assertIn("review 'APPROVED' -> ''", self.check(0))

    def test_both_comment_endpoints_count(self):
        self.save()
        for endpoint in (ISSUE_COMMENTS, REVIEW_COMMENTS):
            with self.subTest(endpoint=endpoint):
                self.responses[endpoint] = [{'id': 42}]
                self.assertIn('comments 0 -> 1', self.check(0))
                self.responses[endpoint] = []

    def test_comments_past_first_page_count(self):
        endpoint = ISSUE_COMMENTS + '&page=2'
        self.responses[ISSUE_COMMENTS] = [{'id': num} for num in range(100)]
        self.responses[endpoint] = []
        self.save()
        self.responses[endpoint] = [{'id': 100}]
        self.assertIn('comments 100 -> 101', self.check(0))

    def test_review_with_only_a_summary_comment(self):
        self.save()
        self.responses[REVIEWS] = [dict(review('COMMENTED'), submitted_at='2026-11-20T10:00:00Z')]
        out = self.check(0)
        self.assertIn('reviews 0 -> 1', out)
        self.assertIn("activity '' -> '2026-11-20T10:00:00Z'", out)

    def test_replaced_or_edited_comment(self):
        self.responses[ISSUE_COMMENTS] = [{'id': 1, 'updated_at': '2026-11-20T10:00:00Z'}]
        self.save()
        self.responses[ISSUE_COMMENTS] = [{'id': 2, 'updated_at': '2026-11-20T11:00:00Z'}]
        self.assertIn("activity '2026-11-20T10:00:00Z' -> '2026-11-20T11:00:00Z'", self.check(0))

    def test_server_with_smaller_pages(self):
        self.responses[ISSUE_COMMENTS] = [{'id': num} for num in range(50)]
        self.responses[ISSUE_COMMENTS + '&page=2'] = [{'id': num} for num in range(50, 60)]
        self.assertEqual(self.save()[f'{REPO}#1']['comments'], 60)

    def test_newly_failing_check_run(self):
        self.save()
        self.responses[CHECKS]['check_runs'][0]['conclusion'] = 'failure'
        self.assertIn("checks 'pass' -> 'fail'; failing [] -> ['unit']", self.check(0))

    def test_newly_failing_commit_status(self):
        self.save()
        self.responses[STATUS] = {'total_count': 1, 'statuses': [{'context': 'build', 'state': 'error'}]}
        self.assertIn("checks 'pass' -> 'fail'; failing [] -> ['build']", self.check(0))

    def test_empty_check_data_is_unknown(self):
        self.responses[CHECKS] = {'total_count': 0, 'check_runs': []}
        self.assertEqual(self.save()[f'{REPO}#1']['checks'], 'unknown')

    def test_merge_changes_state(self):
        self.save()
        self.responses[PULL].update(state='closed', merged=True)
        self.assertIn("state 'open' -> 'closed'; merged False -> True", self.check(0))

    def test_failed_or_non_json_read(self):
        self.save()
        for response, error in (({'$error': 'fake read failed'}, 'fake read failed'),
                                ('not JSON', 'not valid JSON')):
            with self.subTest(response=response):
                self.responses[REVIEWS] = response
                result = self.run_sentinel('check')
                self.assertEqual(result.returncode, 2)
                self.assertIn(REVIEWS, result.stderr)
                self.assertIn(error, result.stderr)
                self.assertEqual(result.stdout, '')

    def test_only_keeps_other_rows(self):
        second = f'repos/{REPO}/pulls/2'
        self.registry.append({'repo': REPO, 'number': 2})
        self.responses.update({
            second: {**self.responses[PULL], 'draft': True},
            f'{second}/reviews?per_page=100': [],
            f'{second}/comments?per_page=100': [],
            f'repos/{REPO}/issues/2/comments?per_page=100': [],
        })
        before = self.save()
        self.responses[PULL]['merged'] = True
        self.responses[PULL]['state'] = 'closed'
        self.responses[second]['draft'] = False
        after = self.save('--only', f'{REPO}#1')
        self.assertTrue(after[f'{REPO}#1']['merged'])
        self.assertEqual(after[f'{REPO}#2'], before[f'{REPO}#2'])
        self.assertEqual(self.check(0).splitlines(), [f'{REPO}#2: draft True -> False'])
