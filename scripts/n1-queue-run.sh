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


def main():
    args = sys.argv[1:]
    require(len(args) >= 2 and args[0] in {'init', 'status', 'select', 'transition'},
            'Usage: init|status|select|transition <queue-id> ...')
    command, queue, *rest = args
    require(ID.fullmatch(queue), 'Invalid queue ID')
    home = os.environ.get('N1_HOME')
    require(home, 'N1_HOME could not be resolved')
    directory = Path(home) / 'queue' / queue
    if command == 'init':
        require(len(rest) >= 3, 'init requires repo, base and explicit tickets')
        repo, base, *tickets = rest
        require(all(ID.fullmatch(ticket) for ticket in tickets)
                and len(set(tickets)) == len(tickets), 'Invalid or duplicate ticket IDs')
        repo = git(repo, 'rev-parse', '--show-toplevel')
        git(repo, 'check-ref-format', 'refs/heads/' + base.removeprefix('refs/heads/'))
        directory.mkdir(parents=True, exist_ok=True)
    else:
        require(directory.is_dir(), 'Queue not found')
    with (directory / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / 'state.json'
        if command == 'init':
            require(not path.exists(), 'Queue already exists; never reset persisted state')
            state = {'version': 1, 'queue_id': queue, 'repo': repo, 'base_ref': base,
                     'base_sha': None, 'revision': 0, 'status': 'pending', 'run_id': None,
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
        if command == 'transition':
            require(len(rest) == 2 and rest[0].isdigit(), 'transition requires revision and JSON file')
            require(state['revision'] == int(rest[0]), 'Revision conflict')
            with open(rest[1]) as source:
                payload = json.load(source)
            transition(state, payload)
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
