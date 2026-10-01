#!/usr/bin/env bash
# Queue transport is deferred; reject before reading or modifying shared state.
echo 'N1 Codex: unattended queue execution is not supported in this milestone.' >&2
exit 2
