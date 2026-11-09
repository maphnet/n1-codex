#!/usr/bin/env python3
"""Persist review provenance and guard an ordinary unattended PR merge."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def require(value, message):
    if not value:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def api(path):
    return json.loads(command('gh', 'api', path))


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False) as out:
        try:
            json.dump(data, out)
            out.write('\n')
            out.flush()
            os.fsync(out.fileno())
            os.replace(out.name, path)
        finally:
            if os.path.exists(out.name):
                os.unlink(out.name)


def remote(repo, branch, head, pr):
    data = api(f'repos/{repo}/pulls/{pr}')
    require(data['number'] == pr and data['state'] == 'open'
            and data['base']['repo']['full_name'] == repo
            and data['head']['repo']['full_name'] == repo
            and data['head']['ref'] == branch and data['head']['sha'] == head,
            'PR identity or head changed')


def eligible(repo, head, pr):
    checks = api(f'repos/{repo}/commits/{head}/check-runs?per_page=100')
    runs = checks['check_runs']
    require(checks['total_count'] == len(runs) and len(runs) < 100, 'Incomplete checks')
    require(all(x['status'] == 'completed' and x['conclusion'] in ('success', 'neutral', 'skipped') for x in runs), 'Checks not passing')
    statuses = api(f'repos/{repo}/commits/{head}/status?per_page=100')
    require(len(statuses['statuses']) < 100 and all(x['state'] == 'success' for x in statuses['statuses']), 'Statuses not passing or incomplete')
    owner, name = repo.split('/')
    query = '''query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){pageInfo{hasNextPage} nodes{isResolved}} latestOpinionatedReviews(first:100){pageInfo{hasNextPage} nodes{state}}}}}'''
    result = json.loads(command('gh', 'api', 'graphql', '-f', 'query='+query, '-f', 'owner='+owner, '-f', 'repo='+name, '-F', 'pr='+str(pr)))
    require(not result.get('errors'), 'Review query failed')
    review = result['data']['repository']['pullRequest']
    for key in ('reviewThreads', 'latestOpinionatedReviews'):
        require(review[key]['pageInfo']['hasNextPage'] is False, 'Incomplete review results')
    require(all(x['isResolved'] is True for x in review['reviewThreads']['nodes']), 'Unresolved review thread')
    require(all(x['state'] != 'CHANGES_REQUESTED' for x in review['latestOpinionatedReviews']['nodes']), 'Changes requested')


def main():
    action, ticket, repo, branch, run, *args = sys.argv[1:]
    require(all((ticket, repo, branch, run)) and '/' in repo, 'Missing identity')
    home = Path(os.environ['N1_HOME'])
    path = home / 'memory' / ticket / 'reviewed-head.json'
    if action == 'record':
        head, tier, code, security = args
        require(tier == 'FULL' and code == 'pass' and security in ('pass', 'not-required'), 'Full review gates required')
        require(not command('git', 'status', '--porcelain') and command('git', 'rev-parse', 'HEAD') == head, 'Review tree changed')
        save(path, dict(repository=repo, branch=branch, head=head, run_id=run, verdict='pass'))
        return
    data = json.loads(path.read_text())
    require(all(data.get(k) == v for k, v in dict(repository=repo, branch=branch, run_id=run, verdict='pass').items()), 'Review identity mismatch')
    head = data['head']
    pr = int(args[0])
    remote(repo, branch, head, pr)
    if action == 'attach':
        data['pr'] = pr
        save(path, data)
        return
    require(action in ('merge', 'interactive-merge') and len(args) == 3, 'Invalid action')
    method, ci = args[1:]
    require(method in ('squash', 'merge', 'rebase') and ci in ('passed', 'no-checks', 'disabled'), 'Invalid merge method or CI state')
    require(data.get('pr') == pr and not os.environ.get('N1_QUEUE_RUN_ID'), 'PR or queue ownership mismatch')
    config = json.loads((home / 'config.json').read_text())
    unattended = action == 'merge'
    require((not unattended and os.environ.get('N1_INTERACTIVE_APPROVED') == 'yes') or
            (unattended and config.get('autonomy', {}).get('fullAuto') is True and config.get('finishWork', {}).get('mergeOnFinish') is True), 'Merge grants missing')
    for state_path in (home / 'queue').glob('*/state.json'):
        state = json.loads(state_path.read_text())
        origin = state.get('origin_repo')
        require(isinstance(origin, str), 'Unknown queue repository')
        require(not ((origin == repo or origin.endswith('/' + repo)) and state.get('integration_ref') == branch), 'Queue final PR is human-owned')
    eligible(repo, head, pr)
    remote(repo, branch, head, pr)
    eligible(repo, head, pr)
    command('gh', 'pr', 'merge', str(pr), '--repo', repo, '--'+method, '--match-head-commit', head, '--delete-branch')
    result = api(f'repos/{repo}/pulls/{pr}')
    require(result.get('merged') is True and result.get('merge_commit_sha'), 'Merge not confirmed')
    print('merged ' + result['merge_commit_sha'])


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f'reviewed-head: {exc}', file=sys.stderr)
        sys.exit(1)
