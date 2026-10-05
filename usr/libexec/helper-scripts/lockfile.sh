#!/bin/bash

## Copyright (C) 2025 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Lock file mechanism to prevent duplicate script instances per user
##
## Two ways to use it:
##   * Source it to self-lock the sourcing script. Only one instance of the
##     script will be able to run at a time.
##   * Execute it as  'lockfile.sh <lock-key> -- <command> [args...]'  to run the
##     command under a per-key lock (skipping, non-zero, if the key is already
##     held).

## Based on flock man page.
## > [ "${FLOCKER}" != "${0}" ] && exec env FLOCKER="${0}" flock -en "${0}" "${0}" "$@" || :

## style-ok: no-strict -- sourced helper.

## style-ok: allow-exec -- process handoff is used here intentionally.

true "${BASH_SOURCE[0]}: START"

true "${BASH_SOURCE[0]}: INFO: FLOCKER: ${FLOCKER-}"

## Lock dir lives under the per-user runtime dir. When there is no logind session
## (root via 'su -', a container, a chroot, 'sudo -u user', ssh without pam_systemd)
## /run/user/EUID does not exist, so fall back to the per-user CACHE dir. Both are
## owned by this user and NOT world-writable, which is the anti-TOCTOU property that
## matters -- the fallbacks rejected by design are SHARED world-writable dirs (/tmp,
## a 1777 dir under /run), where another user could pre-plant a symlink. The checks
## below enforce that property on whichever base is used: a real directory, owned by
## this user, not a symlink.
## The runtime dir is used only when it is a real directory, not a symlink, AND
## owned by this user; otherwise (no session, or an inherited XDG_RUNTIME_DIR that
## points at another user's /run/user, e.g. under 'sudo -u') fall through to the
## cache dir rather than hard-exiting.
flocker_runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${EUID}}"
if [ -d "${flocker_runtime_dir}" ] && [ ! -L "${flocker_runtime_dir}" ] && [ -O "${flocker_runtime_dir}" ]; then
  flocker_base="${flocker_runtime_dir}"
else
  ## ${HOME:-} not ${HOME}: a sourcing caller may run under 'set -o nounset', where
  ## an unset HOME would abort with 'unbound variable' instead of the clear error
  ## below (both unset -> '/.cache', which the ownership check then rejects cleanly).
  flocker_base="${XDG_CACHE_HOME:-${HOME:-}/.cache}"
  mkdir --parents -- "${flocker_base}" 2>/dev/null || true
fi
if [ ! -d "${flocker_base}" ] || [ -L "${flocker_base}" ] || [ ! -O "${flocker_base}" ]; then
  printf '%s\n' "$0: ERROR: no usable per-user lock directory ('${flocker_base}' must be a directory you own and not a symlink)!" 1>&2
  exit 1
fi
flocker_temp_folder="${flocker_base}/flocker-temp-folder"
mkdir --parents -- "${flocker_temp_folder}"
if [ -L "${flocker_temp_folder}" ] || [ ! -O "${flocker_temp_folder}" ]; then
  printf '%s\n' "$0: ERROR: refusing unexpected symlink or non-owned directory at lock directory location '${flocker_temp_folder}'!" 1>&2
  exit 1
fi

## Wrap-mode setup: an EXECUTED run of THIS file with arguments DERIVES the lock
## key from $1 and runs the rest as a command under that key's lock (the run
## happens on the locked pass, below). It triggers only when a key is NOT already
## chosen (LOCK_NAME unset), because wrap mode's whole job is to derive the key;
## if one is set the caller is self-locking, not wrapping. That single test keeps
## wrap mode off for both ways the body runs without being the wrap CLI:
##   - a SOURCED use (BASH_SOURCE[0] != $0), the historical self-lock, and
##   - an INLINED copy pasted into another executed script (e.g. the
##     dist-installer-cli standalone generator), where BASH_SOURCE[0] == $0 at the
##     host's top level: such a host sets LOCK_NAME to its own key, which both
##     fixes its lock file and suppresses wrap mode here. Unlike a basename check,
##     this still lets wrap mode run when lockfile.sh is invoked under a symlink or
##     a different name (no silent no-op of the wrapped command).
lockfile_wrap="no"
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ -z "${LOCK_NAME-}" ] && [ "${#}" -ge 1 ]; then
  lockfile_wrap="yes"
  LOCK_NAME="${1}"
fi

## The lock key defaults to this script's own path. A caller that runs the same
## script concurrently for different keys can set LOCK_NAME to lock per key
## instead.
if [ -n "${LOCK_NAME-}" ]; then
  flocker_key="${LOCK_NAME}"
else
  flocker_key="$(realpath -- "${0}")"
fi

flocker_path_substituted="${flocker_key//_/_underscore_}"
flocker_path_substituted="${flocker_path_substituted//\//_slash_}"
flocker_path_substituted="${flocker_path_substituted//./_dot_}"
flocker_lockfile="${flocker_temp_folder}/${flocker_path_substituted}"

if ! test -f "${flocker_lockfile}"; then
  touch -- "${flocker_lockfile}"
fi

if [ "${FLOCKER-}" != "${0}" ]; then
  true "${BASH_SOURCE[0]}: INFO: FLOCKER set to self: no"

  ## Using 'flock' with option '--verbose' but hiding stdout for the purpose of showing
  ## 'flock: failed to get lock' error message, if applicable.
  ## The error message is not perfectly atomic.
  flock --verbose --exclusive --nonblock "${flocker_lockfile}" /usr/bin/true >/dev/null
  ## But if we were to use '--verbose' below, then 'flock' would always add verbose
  ## output even in case it was possible to acquire a lock.

  if test -o xtrace; then
    ## Code duplication. Also in xtrace.bsh function shellopts_with_xtrace.
    ## This helper intentionally avoids sourcing dependencies.
    ## TODO: Do we need to avoid sourcing dependencies?
    case ":${SHELLOPTS-}:" in
      *:xtrace:*)
        flocker_shellopts="${SHELLOPTS-}"
        ;;
      *)
        flocker_shellopts="${SHELLOPTS-}:xtrace"
        ;;
    esac
    exec env SHELLOPTS="${flocker_shellopts}" FLOCKER="${0}" flock --exclusive --nonblock "${flocker_lockfile}" "${0}" "${@}"
  else
    exec env FLOCKER="${0}" flock --exclusive --nonblock "${flocker_lockfile}" "${0}" "${@}"
  fi
  ## Never reached due to 'exec' above.
fi

## If we get this far, we're in wrap mode. The above code will have re-executed
## this script with the lock held, so now we just need to hand off to the
## target command.
if [ "${lockfile_wrap}" = "yes" ]; then
  shift # Get rid of the lock key name
  if [ "${#}" -ge 1 ] && [ "${1}" = "--" ]; then
    shift # We support end-of-options even though we don't have any options
  fi
  if [ "${#}" -lt 1 ]; then
    printf '%s\n' "${0}: ERROR: usage: ${0} <lock-key> -- <command> [args...]" 1>&2
    exit 2
  fi
  unset LOCK_NAME FLOCKER
  exec -- "${@}"
fi

true "${BASH_SOURCE[0]}: INFO: FLOCKER set to self: yes"

true "${BASH_SOURCE[0]}: END"
