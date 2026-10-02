#!/bin/bash

## Copyright (C) 2025 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## style-ok: no-strict -- sourced library; a top-level strict-mode block
## would leak 'set -o errexit'/'nounset' into the sourcing shell.
##
## style-ok: no-has -- leaprun_useable_test() uses 'command -v' to RESOLVE
## leaprun's path into ${leaprun_exe} (has returns only a boolean).

leaprun_useable_output() {
   printf "%s\n" "${*}" >&2
}

leaprun_useable_test() {
   ## use_leaprun and leaprun_exe are consumed by sourcing scripts.
   # shellcheck disable=SC2034
   use_leaprun='no'

   ## privleap / leaprun is supposed to work fine even if called as root, so
   ## account 'root' gets no special-casing (preference: fail early, hard, noisy).

   # shellcheck disable=SC2034
   if ! leaprun_exe="$(command -v leaprun)"; then
      leaprun_useable_result="${0}: WARNING: leaprun executable cannot be found. Cannot use privleap."
      leaprun_useable_output "${leaprun_useable_result}"
      return 0
   fi

   local my_user_id
   if ! my_user_id="$(id --user)"; then
      leaprun_useable_result="${0}: WARNING: Failed to execute 'id --user'. Cannot use privleap."
      leaprun_useable_output "${leaprun_useable_result}"
      return 0
   fi

   ## privleapd names the per-user comm socket by numeric UID.
   local comm_socket="/run/privleapd/comm/${my_user_id}"

   if ! [ -e "${comm_socket}" ]; then
      leaprun_useable_result="${0}: WARNING: Cannot communicate with privleapd. Socket '${comm_socket}' does not exist. Cannot use privleap.

You might be able to create a privleap socket by executing: sudo leapctl --create '${USER:-${my_user_id}}'"
      leaprun_useable_output "${leaprun_useable_result}"
      return 0
   fi

   ## Authoritative reachability signal: an actual connect() to the AF_UNIX
   ## socket. A pidfile + '/proc/<pid>' heuristic false-NEGATIVES under 'proc'
   ## 'hidepid=2' (privleapd runs as root, so its '/proc/<pid>' is invisible to
   ## this user) and false-POSITIVES on a stale socket left by a crashed daemon
   ## (pid reused, socket inode lingers, no connection possible). Only a
   ## connect() settles both. The probe sends no data, so privleapd triggers no
   ## action.
   local connect_probe
   connect_probe="$(dirname -- "${BASH_SOURCE[0]}")/privleapd_connect_probe.py"
   if ! "${connect_probe}" "${comm_socket}"; then
      leaprun_useable_result="${0}: WARNING: privleapd is not reachable on socket '${comm_socket}' (stale socket, or privleapd not running). Cannot use privleap."
      leaprun_useable_output "${leaprun_useable_result}"
      return 0
   fi

   # shellcheck disable=SC2034
   use_leaprun='yes'
}

leaprun_useable_test
