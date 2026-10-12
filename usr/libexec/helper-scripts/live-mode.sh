#!/bin/bash

## Copyright (C) 2012 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## live_status_* variables are used, but indirectly.
# shellcheck disable=SC2034

true "$0: START"

# shellcheck source=./check_runtime.bsh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/check_runtime.bsh || true
if ! declare -F was_executed >/dev/null; then
  printf '%s\n' "$0: ERROR: cannot source check_runtime.bsh!" >&2
  exit 1
fi
# shellcheck source=./strings.bsh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/strings.bsh

if was_executed "${BASH_SOURCE[0]}"; then
  live_mode_sourced='false'
else
  live_mode_sourced='true'
fi

if [ "${live_mode_sourced}" = 'false' ]; then
  set -o errexit
  set -o nounset
  set -o errtrace
  set -o pipefail
  shopt -s inherit_errexit
  shopt -s shift_verbose
  export LC_ALL=C
fi

if [ -z "${proc_mount_contents+x}" ]; then
  proc_mount_contents="$(cat /proc/self/mounts)"
fi

if [ -z "${livecheck_lsblk_contents+x}" ]; then
  if [ -r '/run/desktop-config-dist/livecheck-lsblk' ]; then
    livecheck_lsblk_contents="$(cat /run/desktop-config-dist/livecheck-lsblk)"
  else
    livecheck_lsblk_contents='0'
  fi
fi

live_state_str='live'
live_mode_str='none'

if [ -z "${kernel_cmdline+x}" ]; then
  kernel_cmdline=''
  if [ -f /proc/cmdline ]; then
    kernel_cmdline="$(cat -- /proc/cmdline)"
  elif [ -f /proc/1/cmdline ]; then
    kernel_cmdline="$(cat -- /proc/1/cmdline)"
  fi
fi

## Opt-in persistent live overlay (the 'Persistent' GRUB submenu boots
## 'rd.live.overlay=LABEL=persistence:/live/overlay'). 'requested' means such an
## entry was booted; 'active' means the overlay actually engaged on a real
## persistence device, as opposed to dmsquash-live's SILENT amnesic RAM fallback
## (no persistence disk, or the overlay/ovlwork dirs missing).
##
## The '/' overlay mount options are IDENTICAL in both cases
## (upperdir=/run/overlayfs,workdir=/run/ovlwork,lowerdir=/run/rootfsbase), so they
## cannot discriminate. The real signal is that dmsquash-live makes /run/overlayfs a
## SYMLINK into the persistence device when it engages, and leaves it a plain tmpfs
## directory on the amnesic fallback. Overridable for tests.
## Note: 'rd.live.overlay=' (with '=' right after 'overlay') matches only the
## persistent entries, never the amnesic base flag 'rd.live.overlay.overlayfs=1'.
live_status_persistence_requested='false'
case "${kernel_cmdline}" in
  *rd.live.overlay=*)
    live_status_persistence_requested='true'
    ;;
esac

if [ -z "${run_overlayfs_is_symlink+x}" ]; then
  if [ -h /run/overlayfs ]; then
    run_overlayfs_is_symlink='true'
  else
    run_overlayfs_is_symlink='false'
  fi
fi

live_status_persistence_active='false'
if [ "${live_status_persistence_requested}" = 'true' ] \
  && [ "${run_overlayfs_is_symlink}" = 'true' ]; then
  live_status_persistence_active='true'
fi

if ! [ -v writable_fs_lists_str ]; then
  writable_fs_lists_str="$(/usr/libexec/helper-scripts/get_writable_fs_lists.sh)"
fi
readarray -t writable_fs_lists <<< "${writable_fs_lists_str}"
IFS=' ' read -r -a safe_writable_fs_list <<< "${writable_fs_lists[0]:-}"
IFS=' ' read -r -a danger_writable_fs_list <<< "${writable_fs_lists[1]:-}"
if [ "${#safe_writable_fs_list[@]}" = '0' ] \
  || [ -z "${safe_writable_fs_list[0]}" ]; then
  safe_writable_list_empty='true'
else
  safe_writable_list_empty='false'
fi
if [ "${#danger_writable_fs_list[@]}" = '0' ] \
  || [ -z "${danger_writable_fs_list[0]}" ]; then
  danger_writable_list_empty='true'
else
  danger_writable_list_empty='false'
fi
for danger_writable_fs in "${danger_writable_fs_list[@]}"; do
  if [ "${danger_writable_fs}" = '/' ]; then
    live_state_str='persistent'
    break
  fi
done

true "INFO: live_state_str: ${live_state_str}"

if [ "${live_state_str}" = 'live' ] \
  && [ "${danger_writable_list_empty}" = 'false' ]; then
  live_state_str='semi-persistent-unsafe'
elif [ "${live_state_str}" = 'live' ] \
  && [ "${safe_writable_list_empty}" = 'false' ]; then
  live_state_str='semi-persistent-safe'
fi

if [ "${live_state_str}" != 'persistent' ]; then
  while read -r line; do
    true "$0: INFO: line: ${line}"
    if [[ "${line}" =~ ^LiveOS_rootfs\ / ]] \
      && [[ "${kernel_cmdline}" =~ rd.live.image ]]; then
      true "$0: INFO: line contains LiveOS_rootfs and kernel_cmdline contains rd.live.image"
      if [ "${live_state_str}" = 'live' ]; then
        live_mode_str='iso-live'
      else
        live_mode_str='iso-live-semi-persistent'
      fi
    fi
  done <<< "${proc_mount_contents}"

  if [ "${live_mode_str}" = 'none' ]; then
    if [ "${live_state_str}" = 'live' ]; then
      live_mode_str='grub-live'
    else
      live_mode_str='grub-live-semi-persistent'
    fi
  fi

  if [ "${live_mode_str}" = 'grub-live' ] && [ "${live_state_str}" = 'live' ]; then
    readarray -t livecheck_lsblk_list <<< "${livecheck_lsblk_contents}"
    all_drives_readonly='true'
    for livecheck_lsblk_line in "${livecheck_lsblk_list[@]}"; do
      if [ "${livecheck_lsblk_line}" != '1' ]; then
        all_drives_readonly='false'
        break
      fi
    done

    if [ "${all_drives_readonly}" = 'true' ]; then
      live_state_str='read-only'
    fi
  fi

  if [ "${live_mode_str}" = 'iso-live' ] && [ "${live_state_str}" = 'live' ]; then
    live_status_detected_live_mode_environment_pretty="ISO Live"
    live_status_detected_live_mode_environment_machine="iso-live"
    live_status_word_pretty="ISO"
    live_status_detected="true"
    live_status_maybe_iso_live_message="<br/><u>This message can be safely ignored if only using this ISO to install to the hard drive.</u><br/>"
  elif [ "${live_mode_str}" = 'iso-live-semi-persistent' ] && [ "${live_state_str}" = 'semi-persistent-safe' ]; then
    live_status_detected_live_mode_environment_pretty="ISO Live (semi-persistent)"
    live_status_detected_live_mode_environment_machine="iso-live-semi-persistent"
    live_status_word_pretty="ISO"
    live_status_detected="true"
    live_status_maybe_iso_live_message="<br/><u>This message can be safely ignored if only using this ISO to install to the hard drive.</u><br/>"
  elif [ "${live_mode_str}" = 'iso-live-semi-persistent' ] && [ "${live_state_str}" = 'semi-persistent-unsafe' ]; then
    live_status_detected_live_mode_environment_pretty="ISO Live (semi-persistent)"
    live_status_detected_live_mode_environment_machine="iso-live-semi-persistent-unsafe"
    live_status_word_pretty="ISO"
    live_status_detected="true"
    live_status_maybe_iso_live_message="<br/><u>This message can be safely ignored if only using this ISO to install to the hard drive.</u><br/>"
  elif [ "${live_mode_str}" = 'grub-live' ] && [ "${live_state_str}" = 'live' ]; then
    live_status_detected_live_mode_environment_pretty="grub-live"
    live_status_detected_live_mode_environment_machine="grub-live"
    live_status_word_pretty="Live"
    live_status_detected="true"
    live_status_maybe_iso_live_message=""
  elif [ "${live_mode_str}" = 'grub-live' ] && [ "${live_state_str}" = 'read-only' ]; then
    live_status_detected_live_mode_environment_pretty="grub-live read-only"
    live_status_detected_live_mode_environment_machine="grub-live-read-only"
    live_status_word_pretty="Read-only"
    live_status_detected="true"
    live_status_maybe_iso_live_message=""
  elif [ "${live_state_str}" = 'semi-persistent-safe' ]; then
    live_status_detected_live_mode_environment_pretty="grub-live-semi-persistent"
    live_status_detected_live_mode_environment_machine="grub-live-semi-persistent"
    live_status_word_pretty="Semi-persistent"
    live_status_detected="true"
    live_status_maybe_iso_live_message=""
  elif [ "${live_state_str}" = 'semi-persistent-unsafe' ]; then
    live_status_detected_live_mode_environment_pretty="grub-live-semi-persistent"
    live_status_detected_live_mode_environment_machine="grub-live-semi-persistent-unsafe"
    live_status_word_pretty="Semi-persistent"
    live_status_detected="true"
    live_status_maybe_iso_live_message=""
  fi
else
  live_status_detected_live_mode_environment_pretty="false"
  live_status_detected_live_mode_environment_machine="false"
  live_status_word_pretty="persistent"
  live_status_detected="false"
  live_status_maybe_iso_live_message=""
fi

if [ "${live_mode_sourced}" = 'false' ]; then
  var_list=(
    "live_status_detected_live_mode_environment_pretty"
    "live_status_detected_live_mode_environment_machine"
    "live_status_word_pretty"
    "live_status_detected"
    "live_status_maybe_iso_live_message"
    "live_status_persistence_requested"
    "live_status_persistence_active"
  )

  ## Print out in format suitable for 'eval' and 'grep'.
  for var_name in "${var_list[@]}"; do
    ## Single quotes. Do not change without reflecting this change by users of this script.
    check_variable_name "${var_name}" || exit 1
    printf '%s\n' "${var_name}='${!var_name}'"
  done
fi

true "$0: END: OK"
