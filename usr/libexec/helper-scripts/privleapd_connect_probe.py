#!/usr/bin/python3 -Bsu

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

"""Reachability probe for a privleapd per-user communication socket.

A pidfile plus '/proc/<pid>' heuristic is unreliable as a liveness test:
  - false NEGATIVE under 'proc' 'hidepid=2': privleapd runs as root, so an
    unprivileged caller cannot see '/proc/<pid>' and wrongly concludes the
    daemon is down;
  - false POSITIVE on a stale pidfile plus a leftover socket: the daemon
    crashed but the pid got reused and the socket inode lingers, so the
    heuristic reports "running" although no connection is possible.

Only an actual connect() to the AF_UNIX stream socket proves privleapd is
listening and reachable for this user. The probe connects and immediately
closes without sending any data, so privleapd triggers no action (its comm
sessions only act on a SIGNAL message the client must send first).

Exit status:
  0  the socket accepted a connection (privleapd reachable)
  1  connect() failed (missing, stale, refused, or permission denied)
  2  usage error
"""

import socket
import sys

## connect() on a local AF_UNIX socket completes near-instantly; the timeout
## only bounds a pathological, non-responsive peer.
CONNECT_TIMEOUT_SECONDS = 2.0


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"{sys.argv[0]}: ERROR: exactly one argument (socket path) required",
            file=sys.stderr,
        )
        return 2
    socket_path = sys.argv[1]
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(CONNECT_TIMEOUT_SECONDS)
            sock.connect(socket_path)
    except OSError:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
