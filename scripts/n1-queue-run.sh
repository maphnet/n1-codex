#!/usr/bin/env bash
# One bounded operation; the coordinator owns tracker and Orca interactions.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
export N1_HOME="$(n1_home)"
exec python3 - "$@" <<'PY'
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')
SHA = re.compile(r'(?:[0-9a-f]{40}|[0-9a-f]{64})\Z')
STATUSES = {'pending', 'blocked', 'launching', 'active', 'paused',
            'succeeded', 'failed', 'stopped'}
CHANGES = {'pending': {'blocked', 'paused', 'stopped'},
           'blocked': {'pending', 'paused', 'stopped'},
           'launching': {'paused', 'failed', 'stopped'},
           'active': {'paused', 'failed', 'stopped'},
           'paused': {'pending', 'stopped'},
           'succeeded': set(), 'failed': set(), 'stopped': set()}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(repo, *args):
    result = subprocess.run(['git', '-C', repo, *args], capture_output=True,
                            text=True, timeout=60)
    require(result.returncode == 0, 'Git verification failed: ' + ' '.join(args))
    return result.stdout.strip()


def origin_identity(repo):
    """Return the provider's canonical host/path identity for this checkout."""
    remote = git(repo, 'config', '--get', 'remote.origin.url')
    if remote.startswith('git@') and ':' in remote:
        host, path = remote[4:].split(':', 1)
        return host + '/' + path.removesuffix('.git')
    parsed = urlsplit(remote)
    if not parsed.hostname and remote:
        return str(Path(remote).expanduser().resolve())
    require(parsed.hostname and parsed.path, 'Origin remote has no canonical identity')
    return parsed.hostname + parsed.path.removesuffix('.git')


def branch_name(value):
    require(isinstance(value, str) and value and not value.startswith('refs/'),
            'Integration target must be a branch name')
    require(not SHA.fullmatch(value) and '@{' not in value and not any(c in value for c in '^~:?*\\\\'),
            'Integration target must be a branch name')
    return value


def save(path, state):
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
            name = out.name
            json.dump(state, out, indent=2)
            out.write('\n')
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def event(state, ticket, transition, reason, **details):
    state['events'].append({'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                            'ticket': ticket, 'transition': transition,
                            'reason': reason, **details})


def validate(state, queue):
    require(isinstance(state, dict) and state.get('version') == 1,
            'Unreadable or unknown-version queue state')
    require(state.get('queue_id') == queue and isinstance(state.get('repo'), str)
            and isinstance(state.get('base_ref'), str), 'Invalid queue identity')
    for key in ('default_ref', 'integration_ref', 'origin_repo', 'integration_sha'):
        require(key in state, 'Missing queue target identity')
    if state['integration_ref'] is not None:
        require(isinstance(state['integration_ref'], str) and isinstance(state['origin_repo'], str)
                and SHA.fullmatch(state['integration_sha']), 'Invalid integration target')
    require(type(state.get('revision')) is int and state['revision'] >= 0
            and state.get('status') in STATUSES, 'Invalid queue revision or status')
    require(isinstance(state.get('tickets'), list) and state['tickets'], 'Invalid tickets')
    seen = set()
    for ticket in state['tickets']:
        require(isinstance(ticket, dict) and isinstance(ticket.get('ticket'), str)
                and ID.fullmatch(ticket['ticket']) and ticket['ticket'] not in seen
                and ticket.get('status') in STATUSES and 'blocker_snapshot' in ticket,
                'Invalid ticket state')
        seen.add(ticket['ticket'])
    require(isinstance(state.get('events'), list) and isinstance(state.get('evidence'), list)
            and all(key in state for key in ('run_id', 'intent', 'receipt')),
            'Missing queue evidence or assignment state')


def transition(state, payload):
    require(isinstance(payload, dict) and set(payload) <= {
        'ticket', 'status', 'reason', 'blocker_snapshot'}, 'Unknown transition fields')
    require(isinstance(payload.get('reason'), str) and payload['reason'].strip(),
            'Transition requires a reason')
    ticket = next((t for t in state['tickets'] if t['ticket'] == payload.get('ticket')), None)
    require(ticket is not None, 'Unknown ticket')
    old = ticket['status']
    new = payload.get('status', old)
    require(new in STATUSES and (new == old or new in CHANGES[old]), 'Invalid status transition')
    require(new != 'pending' or state['intent'] is None,
            'Cannot requeue an uncertain assignment')
    if 'blocker_snapshot' in payload:
        proof = payload['blocker_snapshot']
        require(isinstance(proof, dict) and set(proof) == {'base_sha', 'lookup', 'blockers'}
                and isinstance(proof['base_sha'], str) and SHA.fullmatch(proof['base_sha'])
                and proof['lookup'] in ('verified', 'unknown')
                and isinstance(proof['blockers'], list), 'Invalid blocker snapshot')
        seen = set()
        for blocker in proof['blockers']:
            require(isinstance(blocker, dict) and set(blocker) <= {'ticket', 'merged_sha', 'verified'}
                    and isinstance(blocker.get('ticket'), str) and ID.fullmatch(blocker['ticket'])
                    and blocker['ticket'] not in seen, 'Invalid blocker')
            require('merged_sha' not in blocker or (isinstance(blocker['merged_sha'], str)
                    and SHA.fullmatch(blocker['merged_sha'])), 'Invalid merged SHA')
            require('verified' not in blocker or type(blocker['verified']) is bool,
                    'Invalid blocker verification')
            seen.add(blocker['ticket'])
        if proof['lookup'] == 'unknown' and ticket['blocker_snapshot']:
            previous = ticket['blocker_snapshot']['blockers']
            proof['blockers'] = [b for b in previous if b['ticket'] not in seen] + proof['blockers']
        ticket['blocker_snapshot'] = proof
    ticket['status'] = new
    event(state, ticket['ticket'], old + '->' + new, payload['reason'],
          blocker_snapshot=ticket['blocker_snapshot'])


def select(state):
    reasons = {}
    if state['intent'] is not None or state['status'] in {'paused', 'stopped'} or any(
            t['status'] in {'launching', 'active', 'paused'} for t in state['tickets']):
        return {'selected': None, 'reasons': {'queue': 'Active or uncertain assignment'}, 'state': state}
    repo, base = state['repo'], state['base_ref']
    ref = 'refs/heads/' + base.removeprefix('refs/heads/')
    tracking = 'refs/remotes/origin/' + ref.removeprefix('refs/heads/')
    git(repo, 'fetch', '--no-tags', '--no-write-fetch-head', 'origin', '+' + ref + ':' + tracking)
    sha = git(repo, 'rev-parse', '--verify', tracking + '^{commit}')
    selected = None
    for ticket in state['tickets']:
        if ticket['status'] not in {'pending', 'blocked'}:
            continue
        proof = ticket['blocker_snapshot']
        reason = None
        if not proof or proof['lookup'] != 'verified':
            reason = 'Unknown tracker blocker evidence'
        elif proof['base_sha'] != sha:
            reason = 'Base changed; refresh blocker proof'
        else:
            for blocker in proof['blockers']:
                if blocker.get('verified') is not True or not blocker.get('merged_sha'):
                    reason = 'Unknown merged commit for ' + blocker['ticket']
                    break
                result = subprocess.run(['git', '-C', repo, 'merge-base', '--is-ancestor',
                                         blocker['merged_sha'], sha], capture_output=True, timeout=60)
                if result.returncode != 0:
                    reason = 'Blocker not verified in base: ' + blocker['ticket']
                    break
        old = ticket['status']
        if reason:
            ticket['status'] = 'blocked'
            reasons[ticket['ticket']] = reason
            event(state, ticket['ticket'], old + '->blocked', reason, base_sha=sha)
        elif selected is None:
            selected = ticket
    # Check the remote again after all ancestor checks, before reserving work.
    remote = git(repo, 'ls-remote', '--exit-code', 'origin', ref).split()
    require(remote and remote[0] == sha, 'Base changed during verification; recompute selection')
    state['base_sha'] = sha
    if selected:
        old = selected['status']
        selected['status'] = 'launching'
        state['status'] = 'launching'
        state['intent'] = {'operation': 'selection', 'ticket': selected['ticket'], 'base_sha': sha}
        event(state, selected['ticket'], old + '->launching', 'Reserved verified ticket', base_sha=sha,
              blocker_snapshot=selected['blocker_snapshot'])
    state['revision'] += 1
    return {'selected': selected['ticket'] if selected else None, 'reasons': reasons, 'state': state}


def assigned(state):
    intent = state['intent']
    require(isinstance(intent, dict), 'No reserved assignment')
    return next(t for t in state['tickets'] if t['ticket'] == intent['ticket'])


def pause(state, reason):
    ticket = assigned(state)
    ticket['status'] = state['status'] = 'paused'
    event(state, ticket['ticket'], 'paused', reason)


def launch_intent(state, payload):
    ticket = assigned(state)
    require(not state.get('stop'), 'Stop requested; explicitly resume before mutation')
    operation = payload.get('operation')
    require(state['status'] == 'launching' or (state['status'] == 'active'
            and operation == 'reference-add'), 'Queue is not ready to mutate')
    previous = state['intent']
    require(previous['operation'] in {'selection', 'recorded'},
            'Uncertain mutation; reconcile its exact identity before continuing')
    require(operation in {'run-create', 'task-create', 'worker-start', 'reference-add'},
            'Unsupported external mutation')
    require(payload.get('ticket') == ticket['ticket'] and
            isinstance(payload.get('request_id'), str) and payload['request_id'],
            'Intent requires ticket and request identity')
    require(not any(e.get('request_id') == payload['request_id'] for e in state['evidence']),
            'Request identity already recorded')
    if operation == 'run-create':
        require(state['run_id'] is None, 'Run already established')
    else:
        require(state['run_id'], 'Persist the Run receipt first')
    if operation == 'task-create':
        require(not ticket.get('task_id'), 'Task already established')
    if operation == 'worker-start':
        require(ticket.get('task_id') and not ticket.get('dispatch_id'),
                'Persist the Task receipt first; never start twice')
        require(payload.get('repo') == state['repo'] and payload.get('base') == state['base_ref'],
                'Launch repository or base mismatch')
        placement = payload.get('placement', {})
        require(isinstance(placement, dict), 'Invalid placement')
        require(not placement.get('configured_root'), 'Configured placement cannot be honored')
        if placement.get('mode') == 'existing':
            binding = placement.get('binding', {})
            require(isinstance(binding, dict), 'Invalid workspace binding')
            require(binding.get('verified') is True and binding.get('identity')
                    and binding.get('repo') == state['repo']
                    and binding.get('ticket') == ticket['ticket']
                    and binding.get('branch') == payload.get('expected_branch')
                    and binding.get('branch')
                    and binding.get('conflicting_assignment') is False,
                    'Existing workspace identity, repository, ticket or branch is unproven')
        else:
            require(placement.get('mode') == 'new-top-level'
                    and isinstance(placement.get('repo_selector'), str)
                    and placement['repo_selector'].startswith(('id:', 'path:')),
                    'New workspace requires exact repository selector')
    if operation == 'reference-add':
        require(ticket.get('workspace') and isinstance(payload.get('urls'), list)
                and payload['urls'] and all(isinstance(url, str) and url.startswith('https://')
                                           for url in payload['urls']), 'Reference requires workspace and URLs')
    state['intent'] = {**payload, 'queue_id': state['queue_id'],
                       'run_id': state['run_id'], 'task_id': ticket.get('task_id'),
                       'base_sha': state['base_sha']}
    event(state, ticket['ticket'], 'intent', operation, intent=state['intent'])


def record_receipt(state, payload):
    ticket = assigned(state)
    intent = state['intent']
    require(intent['operation'] not in {'selection', 'recorded'}
            and payload.get('request_id') == intent['request_id'], 'Receipt intent mismatch')
    require(isinstance(payload.get('receipt'), dict) and payload['receipt'], 'Full receipt required')
    state['receipt'] = payload['receipt']
    state['evidence'].append({**payload, 'kind': 'receipt', 'intent': intent})
    identity = payload.get('identity', {})
    require(isinstance(identity, dict) and set(identity) <= {
        'run_id', 'task_id', 'dispatch_id', 'workspace', 'branch', 'repo', 'ticket',
        'terminal', 'terminal_id'}, 'Invalid receipt identity')
    operation = intent['operation']
    keys = {'run-create': ('run_id',), 'task-create': ('task_id',),
            'worker-start': ('dispatch_id', 'workspace', 'branch'), 'reference-add': ()}[operation]
    if payload.get('verified') is not True or not all(
            isinstance(identity.get(key), str) and identity[key] for key in keys):
        pause(state, 'Uncertain external result; inspect receipt recovery and exact identities')
        return
    if operation == 'run-create':
        state['run_id'] = identity['run_id']
    elif operation == 'task-create':
        ticket['task_id'] = identity['task_id']
    elif operation == 'worker-start':
        # New branches come from the receipt; existing branches must match the binding.
        placement = intent['placement']
        if identity.get('repo') != state['repo'] or identity.get('ticket') != ticket['ticket'] or (
                intent.get('expected_branch') and identity['branch'] != intent['expected_branch']) or (
                placement['mode'] == 'existing' and identity['workspace'] != placement['binding']['identity']):
            pause(state, 'Returned workspace or branch conflicts with launch intent')
            return
        ticket.update({key: value for key, value in identity.items()
                       if key in {'dispatch_id', 'workspace', 'branch', 'repo', 'terminal', 'terminal_id'}})
        if state.get('stop'):
            state['stop']['dispatch_id'] = identity['dispatch_id']
        ticket['status'] = state['status'] = 'paused' if state.get('stop') else 'active'
    state['intent'] = {**intent, 'operation': 'recorded', 'completed_operation': operation}
    event(state, ticket['ticket'], 'receipt', operation, identity=identity)


def wake(state, payload):
    assigned(state)
    require(isinstance(payload.get('receipt'), dict) and isinstance(payload.get('messages'), list)
            and all(isinstance(message, dict) for message in payload['messages']),
            'Wake requires full check receipt and messages')
    state['evidence'].append({**payload, 'kind': 'wake'})
    if any(message.get('type') in {'question', 'escalation', 'permission'}
           for message in payload['messages']):
        pause(state, 'Worker needs coordinator or user attention')


def stop(state, payload):
    require(isinstance(payload.get('reason'), str) and payload['reason'].strip(),
            'Stop requires a reason')
    require(not state.get('stop'), 'Stop already requested; reconcile its result')
    ticket = assigned(state) if state['intent'] else None
    dispatch = ticket.get('dispatch_id') if ticket else None
    state['stop'] = {'reason': payload['reason'], 'dispatch_id': dispatch}
    state['status'] = 'paused' if state['intent'] else 'stopped'
    if ticket:
        ticket['status'] = 'paused'
    event(state, ticket['ticket'] if ticket else None, 'stop-requested', payload['reason'],
          dispatch_id=dispatch)


def stop_result(state, payload):
    request = state.get('stop')
    require(request and request.get('dispatch_id') and
            payload.get('dispatch_id') == request['dispatch_id'], 'Stop assignment mismatch')
    require(isinstance(payload.get('receipt'), dict) and payload['receipt'],
            'Full stop receipt required')
    state['evidence'].append({**payload, 'kind': 'stop-result'})
    settled = payload.get('verified') is True and payload.get('settled') is True
    request['settled'] = settled
    state['status'] = 'stopped' if settled else 'paused'
    assigned(state)['status'] = state['status']
    event(state, state['intent']['ticket'], 'stop-result',
          'Verified settled stop' if settled else 'Stop or liveness uncertain')


def resume(state, payload):
    require(state['status'] in {'paused', 'stopped'}, 'Queue is not paused or stopped')
    require(isinstance(payload.get('reason'), str) and payload['reason'].strip(),
            'Resume requires a reason')
    if state['run_id']:
        require(payload.get('run_id') == state['run_id'] and payload.get('verified') is True
                and isinstance(payload.get('receipt'), dict) and payload['receipt'],
                'Rebind and verify the original Run before resume')
    state['evidence'].append({**payload, 'kind': 'resume'})
    intent = state['intent']
    if intent:
        ticket = assigned(state)
        if state.get('stop', {}).get('settled') is True:
            ticket['status'] = 'stopped'
            state['intent'] = None
        elif intent['operation'] == 'selection':
            ticket['status'] = 'pending'
            state['intent'] = None
        elif intent['operation'] != 'recorded':
            pause(state, 'Reconcile the persisted mutation receipt before resuming')
            return
        elif ticket.get('dispatch_id'):
            identity = payload.get('assignment', {})
            require(isinstance(identity, dict), 'Invalid reconciled assignment')
            settled = identity.get('active') is False and identity.get('settled') is True and any(
                message.get('type') == 'worker_done' and message.get('dispatch_id') == ticket['dispatch_id']
                and message.get('settled') is True for evidence in state['evidence']
                if evidence.get('kind') == 'wake' for message in evidence['messages'])
            if not (identity.get('active') is True or settled) or not all(
                    identity.get(key) == ticket.get(key) for key in
                    ('dispatch_id', 'workspace', 'repo', 'branch', 'ticket')):
                pause(state, 'Original assignment liveness or identity remains uncertain')
                return
            ticket['status'] = state['status'] = 'active'
        else:
            ticket['status'] = state['status'] = 'launching'
    if state['intent'] is None:
        state['status'] = 'pending'
    state.pop('stop', None)
    # Resume invalidates tracker proofs so selection always rechecks the current base.
    for ticket in state['tickets']:
        if ticket['status'] in {'pending', 'blocked'} and ticket['blocker_snapshot']:
            ticket['blocker_snapshot']['lookup'] = 'unknown'
    event(state, intent['ticket'] if intent else None, 'resumed', payload['reason'])


def completion(state, payload):
    ticket = assigned(state)
    require(state['status'] == 'active' and ticket['status'] == 'active',
            'Completion requires an active assignment; resolve the pause before resuming')
    require(ticket.get('dispatch_id') and payload.get('dispatch_id') == ticket['dispatch_id'],
            'Completion assignment mismatch')
    done, pr, verified, ci = (payload.get(key, {}) for key in
                              ('worker_done', 'pr', 'verified_pr', 'ci'))
    require(all(isinstance(value, dict) for value in (done, pr, verified, ci)),
            'Invalid completion evidence')
    checks, expected = ci.get('checks', []), ci.get('expected', [])
    require(isinstance(checks, list) and all(isinstance(check, dict) for check in checks),
            'Invalid provider checks')
    state['evidence'].append({**payload, 'kind': 'completion'})
    commit = ci.get('commit')
    remote = subprocess.run(['git', '-C', state['repo'], 'config', '--get', 'remote.origin.url'],
                            capture_output=True, text=True, timeout=60).stdout.strip()
    match = re.fullmatch(r'(?:https://|ssh://(?:[^@/]+@)?)([^/:]+(?::[0-9]+)?)/(.+?)(?:\.git)?/?', remote)
    if not match:
        match = re.fullmatch(r'[^@/]+@([^:]+):(.+?)(?:\.git)?/?', remote)
    url = urlsplit(pr.get('url', '') if isinstance(pr.get('url'), str) else '')
    canonical = bool(match and url.scheme == 'https' and url.netloc.lower() == match.group(1).lower()
                     and pr.get('repo') == match.group(2)
                     and url.path.startswith('/' + match.group(2) + '/'))
    settled = any(message.get('type') == 'worker_done'
                  and message.get('dispatch_id') == ticket['dispatch_id']
                  and message.get('outcome') == 'succeeded' and message.get('settled') is True
                  for evidence in state['evidence'] if evidence.get('kind') == 'wake'
                  for message in evidence['messages'])
    valid = (settled and state['intent']['operation'] == 'recorded'
             and done.get('outcome') == 'succeeded' and done.get('settled') is True
             and payload.get('workflow_complete') is True
             and isinstance(pr.get('url'), str) and pr['url'].startswith('https://')
             and canonical and pr.get('repo') == verified.get('repo')
             and pr.get('branch') == verified.get('branch') == ticket['branch']
             and isinstance(pr.get('head'), str) and SHA.fullmatch(pr['head'])
             and pr['head'] == verified.get('head')
             and (commit == pr['head'] or (commit == verified.get('test_merge_commit')
                  and verified.get('test_merge_head') == pr['head']))
             and isinstance(expected, list) and expected
             and all(isinstance(name, str) and name for name in expected)
             and len(expected) == len(set(expected))
             and isinstance(checks, list)
             and all(any(check.get('identity') == name and check.get('commit') == commit
                         and check.get('conclusion') == 'success' for check in checks)
                     for name in expected)
             and all(check.get('commit') == commit and check.get('conclusion') == 'success'
                     for check in checks))
    if not valid:
        pause(state, 'Missing, stale, failed or inaccessible worker/PR/workflow/CI evidence')
        return
    ticket['status'] = 'succeeded'
    state['status'] = 'succeeded' if all(t['status'] == 'succeeded' for t in state['tickets']) else 'pending'
    state['intent'] = None
    event(state, ticket['ticket'], 'succeeded', 'Settled worker and matching PR/workflow/CI evidence')


def main():
    args = sys.argv[1:]
    operations = {'transition': transition, 'intent': launch_intent, 'receipt': record_receipt,
                  'wake': wake, 'evidence': completion, 'stop': stop,
                  'stop-result': stop_result, 'resume': resume}
    require(len(args) >= 2 and args[0] in {'init', 'status', 'select'} | operations.keys(),
            'Usage: init|status|select|transition|intent|receipt|wake|evidence|stop|stop-result|resume <queue-id> ...')
    command, queue, *rest = args
    require(ID.fullmatch(queue), 'Invalid queue ID')
    home = os.environ.get('N1_HOME')
    require(home, 'N1_HOME could not be resolved')
    directory = Path(home) / 'queue' / queue
    if command == 'init':
        require(len(rest) >= 3, 'init requires repo, base and explicit tickets')
        repo, base, *items = rest
        grant = None
        if '--grant' in items:
            index = items.index('--grant')
            require(index + 1 < len(items), 'init --grant requires a JSON file')
            with open(items[index + 1]) as source:
                grant = json.load(source)
            items = items[:index] + items[index + 2:]
        tickets = items
        require(all(ID.fullmatch(ticket) for ticket in tickets)
                and len(set(tickets)) == len(tickets), 'Invalid or duplicate ticket IDs')
        repo = git(repo, 'rev-parse', '--show-toplevel')
        base = branch_name(base)
        git(repo, 'check-ref-format', '--branch', base)
        origin = origin_identity(repo)
        default_ref, integration_ref, integration_sha = base, None, None
        if grant is not None:
            require(isinstance(grant, dict), 'Invalid integration grant')
            require(grant.get('repo') == repo and grant.get('origin') == origin,
                    'Integration grant repository or origin mismatch')
            require(grant.get('default_ref') == base and grant.get('approval', {}).get('scope') == 'integration-only'
                    and isinstance(grant.get('approval', {}).get('source'), str)
                    and grant['approval']['source'].strip(), 'Invalid integration approval')
            integration_ref = branch_name(grant.get('integration_ref'))
            require(integration_ref != base, 'Integration target cannot be the default branch')
            git(repo, 'check-ref-format', '--branch', integration_ref)
            remote_default = git(repo, 'ls-remote', '--exit-code', 'origin', 'refs/heads/' + base).split()
            require(remote_default and SHA.fullmatch(remote_default[0]), 'Default branch is unavailable')
            target = 'refs/heads/' + integration_ref
            tracking = 'refs/remotes/origin/' + integration_ref
            git(repo, 'fetch', '--no-tags', '--no-write-fetch-head', 'origin', '+' + target + ':' + tracking)
            integration_sha = git(repo, 'rev-parse', '--verify', tracking + '^{commit}')
            require(SHA.fullmatch(integration_sha), 'Integration target tip is unavailable')
        directory.mkdir(parents=True, exist_ok=True)
    else:
        require(directory.is_dir(), 'Queue not found')
    with (directory / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / 'state.json'
        if command == 'init':
            require(not path.exists(), 'Queue already exists; never reset persisted state')
            state = {'version': 1, 'queue_id': queue, 'repo': repo,
                     'base_ref': integration_ref or base,
                     'default_ref': default_ref, 'integration_ref': integration_ref,
                     'origin_repo': origin, 'integration_sha': integration_sha,
                     'base_sha': integration_sha, 'revision': 0, 'status': 'pending', 'run_id': None,
                     'intent': None, 'receipt': None, 'evidence': [], 'events': [],
                     'tickets': [{'ticket': ticket, 'status': 'pending', 'blocker_snapshot': None}
                                 for ticket in tickets]}
            event(state, None, 'initialized', 'Explicit ordered ticket list')
            save(path, state)
            return state
        with path.open() as source:
            state = json.load(source)
        validate(state, queue)
        if command == 'status':
            require(not rest, 'status takes only a queue ID')
            return state
        if command in operations:
            require(len(rest) == 2 and rest[0].isdigit(), 'Operation requires revision and JSON file')
            require(state['revision'] == int(rest[0]), 'Revision conflict')
            with open(rest[1]) as source:
                payload = json.load(source)
            require(isinstance(payload, dict), 'Operation requires a JSON object')
            operations[command](state, payload)
            state['revision'] += 1
            result = state
        else:
            require(not rest, 'select takes only a queue ID')
            result = select(state)
        save(path, state)
        return result


try:
    print(json.dumps(main()))
except (ValueError, OSError, TypeError, KeyError, subprocess.SubprocessError) as error:
    print(json.dumps({'error': str(error)}))
    sys.exit(2)
PY
