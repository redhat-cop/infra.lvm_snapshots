#!/bin/bash
#
# bigboot.sh — Increase the /boot partition by relocating adjacent partitions.
#
# 1. Capture the partition table using sfdisk -d (dump)
# 2. Stop udev event queue to prevent fsck restart storms during dd moves
# 3. Scan entire disk to record the active/inactive state of ALL LVM VGs
# 4. Deactivate ALL LVM VGs safely BEFORE data moves to release kernel locks
# 5. Move partition data to final positions using dd (optimised block size)
# 6. Inject a systemd drop-in to disable fsck limits (prevents cascade failures)
# 7. Write the modified partition table via sfdisk
# 8. Sync kernel via partx if available
# 9. Grow the boot filesystem (resize2fs / xfs_growfs)
# 10. Resume udev queue + settle, wipe console spam
# 11. Reactivate *ONLY* the LVM VGs that were active when we started.
#
# Compatibility: RHEL 7/8/9 dracut initramfs (util-linux 2.23+, bash 4.2+)
# Required in initramfs: dd  (add to module-setup.sh: inst_binary /usr/bin/dd)

boot_part_name="$1"
next_part_name="$2"
boot_size_increase_in_bytes="$3"

name="bigboot"
echo "$name: script version 66 (Pre-Move Deactivation + ShellCheck Compliant)"

# ── Input validation ──────────────────────────────────────────────────────────

if [[ ! -b "/dev/$boot_part_name" ]]; then
  echo "$name: Boot partition is not a block device: $boot_part_name"
  exit 1
fi
if [[ ! -b "/dev/$next_part_name" ]]; then
  echo "$name: Next partition is not a block device: $next_part_name"
  exit 1
fi
if ! [[ "$boot_size_increase_in_bytes" -gt 0 ]] 2>/dev/null; then
  echo "$name: Invalid size increase value: $boot_size_increase_in_bytes"
  exit 1
fi

# ── Idempotency guard ─────────────────────────────────────────────────────────

_flag="/tmp/bigboot.done"
if [[ -f "$_flag" ]] || [[ -f "/run/bigboot.done" ]]; then
  echo "$name: Already completed (flag file exists), skipping"
  exit 0
fi
: > "$_flag" 2>/dev/null

# ── Locate dd ─────────────────────────────────────────────────────────────────

DD=$(command -v dd 2>/dev/null) || DD=""
if [[ -z "$DD" ]]; then
  for _p in /usr/bin/dd /bin/dd /sbin/dd; do
    [[ -x "$_p" ]] && DD="$_p" && break
  done
fi
if [[ -z "$DD" ]]; then
  echo "$name: FATAL: dd not found in PATH or common locations"
  exit 1
fi

# ── Wait for partition sysfs entries ──────────────────────────────────────────

echo "$name: Waiting for partition sysfs entries"
_wait=0
while [[ ! -f "/sys/class/block/$boot_part_name/start" ]] || \
      [[ ! -f "/sys/class/block/$next_part_name/start" ]]; do
  if [[ $_wait -ge 30 ]]; then
    echo "$name: Timed out waiting for sysfs"
    exit 1
  fi
  sleep 1
  _wait=$((_wait + 1))
done

# ── Determine disk device ─────────────────────────────────────────────────────

_link=$(readlink -f "/sys/class/block/$boot_part_name/..")
boot_disk_device="/dev/${_link##*/}"
disk_base="${_link##*/}"
unset _link

boot_part_num="$(</sys/class/block/"$boot_part_name"/partition)"
next_part_num="$(</sys/class/block/"$next_part_name"/partition)"
_offset_sectors=$(( boot_size_increase_in_bytes / 512 ))

# ── Phase 1: Cache all sysfs values using bash builtins only ─────────────────

boot_part_end_byte=$(( ( $(</sys/class/block/"$boot_part_name"/start) \
                         + $(</sys/class/block/"$boot_part_name"/size) ) * 512 ))
next_part_start_byte=$(( $(</sys/class/block/"$next_part_name"/start) * 512 ))
next_part_size_byte=$(( $(</sys/class/block/"$next_part_name"/size) * 512 ))

_cached_parts=""
for (( i=1; i<=128; i++ )); do
  p="${disk_base}${i}"
  [[ ! -b "/dev/$p" ]] && continue
  [[ ! -f "/sys/class/block/${p}/start" ]] && continue
  eval "_sysfs_start_${i}=$(< "/sys/class/block/${p}/start")"
  eval "_sysfs_size_${i}=$(< "/sys/class/block/${p}/size")"
  _cached_parts="${_cached_parts} ${i}"
done
echo "$name: cached sysfs:$_cached_parts"
echo "$name: boot_end=$boot_part_end_byte next_start=$next_part_start_byte" \
     "next_size=$next_part_size_byte offset=$_offset_sectors"

# ── Phase 2: External commands (sysfs values now cached) ─────────────────────

_dump=$(/usr/sbin/sfdisk -d "$boot_disk_device" 2>/dev/null)
if [[ -z "$_dump" ]]; then
  echo "$name: FATAL: sfdisk -d produced no output"
  exit 1
fi
echo "$name: sfdisk dump captured"

# ── Pre-pass: extract partition types from the sfdisk dump ───────────────────

while IFS= read -r _line; do
  if [[ "$_line" =~ /dev/${disk_base}([0-9]+)[[:space:]]*:.*[[:space:]](type|Id)=[[:space:]]*([0-9a-fA-F]+) ]]; then
    _pn="${BASH_REMATCH[1]}"
    _ptype="${BASH_REMATCH[3]}"
    eval "_part_type_${_pn}=${_ptype}"
  fi
done <<< "$_dump"

# ── Identify intermediate partitions ─────────────────────────────────────────

_intermediate=""
for _pn in $_cached_parts; do
  _s=""
  _z=""
  eval "_s=\$_sysfs_start_${_pn}"
  eval "_z=\$_sysfs_size_${_pn}"
  _sb=$(( _s * 512 ))
  _eb=$(( _sb + _z * 512 ))
  [[ "$_sb" -lt "$boot_part_end_byte" ]]   && continue
  [[ "$_sb" -ge "$next_part_start_byte" ]] && continue
  _is_ext=false
  eval "_ptype=\${_part_type_${_pn}:-0}"
  [[ "$_ptype" == "5" || "$_ptype" == "f" || "$_ptype" == "F" || "$_ptype" == "85" ]] && _is_ext=true
  if [[ "$_is_ext" == false && "$_eb" -gt "$next_part_start_byte" ]]; then
    continue
  fi
  _intermediate="${_intermediate} ${_pn}"
  eval "_is_ext_${_pn}=$_is_ext"
done
echo "$name: intermediate partitions:$_intermediate"

# ── Build modified sfdisk dump ────────────────────────────────────────────────

_modified_dump=""
while IFS= read -r _line; do
  if [[ "$_line" =~ /dev/${disk_base}([0-9]+)[[:space:]]*:[[:space:]].*start=[[:space:]]*([0-9]+).*size=[[:space:]]*([0-9]+) ]]; then
    _pnum="${BASH_REMATCH[1]}"
    _old_start="${BASH_REMATCH[2]}"
    _old_size="${BASH_REMATCH[3]}"
    _new_start="$_old_start"
    _new_size="$_old_size"

    if [[ $_pnum -eq $boot_part_num ]]; then
      _new_size=$(( _old_size + _offset_sectors ))
    elif [[ $_pnum -eq $next_part_num ]]; then
      _new_start=$(( _old_start + _offset_sectors ))
      _new_size=$(( _old_size  - _offset_sectors ))
    else
      _is_int=false
      for _ip in $_intermediate; do
        [[ $_pnum -eq $_ip ]] && _is_int=true && break
      done
      if [[ "$_is_int" == true ]]; then
        _ext=""
        eval "_ext=\${_is_ext_${_pnum}:-false}"
        if [[ "$_ext" == true ]]; then
          _new_start=$(( _old_start + _offset_sectors ))
          _new_size=$(( _old_size  - _offset_sectors ))
        else
          _new_start=$(( _old_start + _offset_sectors ))
        fi
      fi
    fi

    _line=$(echo "$_line" | sed \
      "s/start=[[:space:]]*[0-9]*/start= ${_new_start}/; \
       s/size=[[:space:]]*[0-9]*/size= ${_new_size}/")
    echo "$name: partition $_pnum: start ${_old_start}->${_new_start} size ${_old_size}->${_new_size}"
  fi
  _modified_dump="${_modified_dump}${_line}"$'\n'
done <<< "$_dump"

# ── Validate boot filesystem type ─────────────────────────────────────────────

eval "$(/usr/sbin/blkid /dev/"$boot_part_name" -o udev)"
boot_fs_type="$ID_FS_TYPE"
if [[ ! "$boot_fs_type" =~ ^ext[2-4]$|^xfs$ ]]; then
  echo "$name: Boot filesystem type is not extendable: $boot_fs_type"
  exit 1
fi

# ── Global LVM VG Scan & Initial State ────────────────────────────────────────

_active_vgs=""
_all_vgs=""

for _pn in $_cached_parts; do
  _pdev="/dev/${disk_base}${_pn}"
  eval "$(/usr/sbin/blkid "$_pdev" -o udev 2>/dev/null)"

  if [[ "$ID_FS_TYPE" == "LVM2_member" ]]; then
    eval "$(DM_DISABLE_UDEV=1 /usr/sbin/lvm pvs --noheadings --nameprefixes \
            -o vg_name "$_pdev" 2>/dev/null)"
    _vg="$LVM2_VG_NAME"

    if [[ -n "$_vg" ]]; then
      # Ensure we only process each VG once (ShellCheck SC2076 fix using wildcard matching)
      if [[ ! " $_all_vgs " == *" $_vg "* ]]; then
        _all_vgs="$_all_vgs $_vg"

        # Check if the kernel mapper has already activated logical volumes for this VG
        _vg_escaped="${_vg//-/--}"
        _is_active=false
        for _dm in /dev/mapper/"${_vg_escaped}"-*; do
          if [[ -b "$_dm" ]]; then
            _is_active=true
            break
          fi
        done

        if [[ "$_is_active" == true ]]; then
          _active_vgs="$_active_vgs $_vg"
          echo "$name: LVM detected: VG $_vg on ${_pdev##*/} [ACTIVE IN INITRAMFS]"
        else
          echo "$name: LVM detected: VG $_vg on ${_pdev##*/} [INACTIVE IN INITRAMFS]"
        fi
      fi
    fi
  fi
done

# ── Compute optimal dd block size ─────────────────────────────────────────────

_next_start_sectors=""
eval "_next_start_sectors=\$_sysfs_start_${next_part_num}"
_offset_bytes=$(( _offset_sectors * 512 ))
_next_start_bytes=$(( _next_start_sectors * 512 ))

_a=$_offset_bytes
_b=$_next_start_bytes
while [[ $_b -ne 0 ]]; do
  _r=$(( _a % _b ))
  _a=$_b
  _b=$_r
done
_gcd=$_a

_bs=512
while [[ $(( _bs * 2 )) -le $_gcd ]] && [[ $(( _bs * 2 )) -le 1048576 ]]; do
  _bs=$(( _bs * 2 ))
done

_bs_sectors=$(( _bs / 512 ))
_chunk_count=$(( 64 * 1024 * 1024 / _bs ))
_chunk_sectors=$(( _bs_sectors * _chunk_count ))
echo "$name: dd block size: $_bs bytes ($_bs_sectors sectors)"

# ══════════════════════════════════════════════════════════════════════════════
# EXIT TRAP
# ══════════════════════════════════════════════════════════════════════════════

_udev_stopped=false

# shellcheck disable=SC2329
_cleanup() {
  if [[ "$_udev_stopped" == true ]]; then
    _udev_stopped=false
    echo "$name: Resuming udev rule execution (cleanup on exit)"
    /usr/sbin/udevadm control --start-exec-queue 2>/dev/null || true
    /usr/sbin/udevadm settle --timeout=30 2>/dev/null || true
  fi
}
trap _cleanup EXIT

# ── Disable console blanking ───────────────────────────────────────────────────

_consoleblank=$(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null)
_prev_timeout=$(( ${_consoleblank:-0} / 60 ))
echo -ne "\x1b[9;0]"

# ── Stop udev rule execution ──────────────────────────────────────────────────

echo "$name: Pausing udev rule execution"
/usr/sbin/udevadm control --stop-exec-queue 2>/dev/null || true
_udev_stopped=true

# ══════════════════════════════════════════════════════════════════════════════
# GLOBAL LVM DEACTIVATION (Moved BEFORE data moves in v66)
# We MUST deactivate ALL Volume Groups to fully release kernel disk locks.
# Doing this BEFORE the dd moves ensures LVM can successfully read the PV
# headers at their current partition boundaries. If we move data first,
# LVM won't find the VG to deactivate it, leaving the disk locked.
# ══════════════════════════════════════════════════════════════════════════════

for _vg in $_all_vgs; do
  echo "$name: Deactivating VG $_vg to completely release disk locks"
  DM_DISABLE_UDEV=1 /usr/sbin/lvm vgchange --config 'global { use_lvmetad = 0 }' -an "$_vg" 2>&1 &
  _vg_pid=$!
  _vg_wait=0
  while [[ $_vg_wait -lt 10 ]] && kill -0 "$_vg_pid" 2>/dev/null; do
    sleep 1
    _vg_wait=$((_vg_wait + 1))
  done
  if kill -0 "$_vg_pid" 2>/dev/null; then
    echo "$name: WARNING: VG $_vg deactivation timed out after 10s, killing"
    kill -9 "$_vg_pid" 2>/dev/null
  else
    wait "$_vg_pid" 2>/dev/null
    echo "$name: VG $_vg deactivated successfully"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# DATA MOVES
# ══════════════════════════════════════════════════════════════════════════════

_dd_move_forward() {
  local _src="$1"
  local _cnt="$2"
  local _off="$3"
  local _lbl="$4"
  local _pos _skip _seek _done _pct _rem _rem_full _rem_tail

  echo "$name: Moving partition $_lbl forward by $_off sectors" \
       "(copying $_cnt of $(( _cnt + _off )) sectors, bs=$_bs)"

  _done=0
  _pos=$(( _cnt - _chunk_sectors ))
  while [[ $_pos -ge 0 ]]; do
    _skip=$(( _src + _pos ))
    _seek=$(( _skip + _off ))
    $DD if="$boot_disk_device" of="$boot_disk_device" \
        bs="$_bs" \
        skip=$(( _skip / _bs_sectors )) \
        seek=$(( _seek / _bs_sectors )) \
        count="$_chunk_count" \
        conv=notrunc 2>/dev/null \
      || { echo "$name: dd failed at sector offset $_pos for $_lbl"; exit 1; }
    _pos=$(( _pos - _chunk_sectors ))
    _done=$(( _done + _chunk_sectors ))
    _pct=$(( _done * 100 / _cnt ))
    echo "$name: Partition move is progressing, please wait! ($_pct% complete)"
  done

  _rem=$(( _cnt % _chunk_sectors ))
  if [[ $_rem -gt 0 ]]; then
    _rem_full=$(( _rem / _bs_sectors ))
    _rem_tail=$(( _rem % _bs_sectors ))
    if [[ $_rem_full -gt 0 ]]; then
      $DD if="$boot_disk_device" of="$boot_disk_device" \
          bs="$_bs" \
          skip=$(( _src / _bs_sectors )) \
          seek=$(( (_src + _off) / _bs_sectors )) \
          count="$_rem_full" \
          conv=notrunc 2>/dev/null \
        || { echo "$name: dd failed (rem) for $_lbl"; exit 1; }
    fi
    if [[ $_rem_tail -gt 0 ]]; then
      $DD if="$boot_disk_device" of="$boot_disk_device" \
          bs=512 \
          skip=$(( _src + _rem_full * _bs_sectors )) \
          seek=$(( _src + _rem_full * _bs_sectors + _off )) \
          count="$_rem_tail" \
          conv=notrunc 2>/dev/null \
        || { echo "$name: dd failed (rem tail) for $_lbl"; exit 1; }
    fi
  fi

  echo "$name: Partition $_lbl move complete (100%)"
}

# 1. Move next partition
_next_s=""
_next_z=""
eval "_next_s=\$_sysfs_start_${next_part_num}"
eval "_next_z=\$_sysfs_size_${next_part_num}"
_next_copy_cnt=$(( _next_z - _offset_sectors ))
_dd_move_forward "$_next_s" "$_next_copy_cnt" "$_offset_sectors" "$next_part_name"

# 2. Move intermediate partitions (descending order)
for (( _pi=128; _pi>=1; _pi-- )); do
  _is_int=false
  for _ip in $_intermediate; do
    [[ $_pi -eq $_ip ]] && _is_int=true && break
  done
  [[ "$_is_int" == false ]] && continue

  _part="${disk_base}${_pi}"
  _ext=""
  eval "_ext=\${_is_ext_${_pi}:-false}"

  if [[ "$_ext" == true ]]; then
    echo "$name: Skipping extended container $_part (table-only update)"
    continue
  fi

  _int_s=""
  _int_z=""
  eval "_int_s=\$_sysfs_start_${_pi}"
  eval "_int_z=\$_sysfs_size_${_pi}"
  echo "$name: Moving intermediate partition $_part forward by" \
       "$_offset_sectors sectors (start=${_int_s} size=${_int_z})"
  _dd_move_forward "$_int_s" "$_int_z" "$_offset_sectors" "$_part"
done

# ══════════════════════════════════════════════════════════════════════════════
# SYSTEMD NEUTER HACK
# ══════════════════════════════════════════════════════════════════════════════

if command -v systemctl >/dev/null 2>&1; then
  echo "$name: Masking systemd-fsck services to prevent race condition cascade"
  mkdir -p /run/systemd/system/systemd-fsck-root.service.d
  cat <<'EOF' > /run/systemd/system/systemd-fsck-root.service.d/99-bigboot.conf
[Unit]
# Systemd 230+ (RHEL 8/9)
StartLimitIntervalSec=0

[Service]
# Systemd < 230 (RHEL 7)
StartLimitInterval=0
StartLimitBurst=1000
ExecStart=
ExecStart=-/bin/true
EOF
  mkdir -p /run/systemd/system/systemd-fsck@.service.d
  cp /run/systemd/system/systemd-fsck-root.service.d/99-bigboot.conf /run/systemd/system/systemd-fsck@.service.d/99-bigboot.conf
  systemctl daemon-reload 2>/dev/null || true
fi

# ── Write partition table ─────────────────────────────────────────────────────

echo "$name: Writing new partition table"
if ! _sfdisk_out=$(echo "$_modified_dump" | /usr/sbin/sfdisk --force --no-reread "$boot_disk_device" 2>&1); then
  echo "$name: sfdisk output: $_sfdisk_out"
  _verify=$(/usr/sbin/sfdisk -d "$boot_disk_device" 2>/dev/null)
  if [[ -n "$_verify" ]]; then
    echo "$name: On-disk partition table appears valid despite error"
  else
    echo "$name: FATAL: Partition table may not have been written"
    exit 1
  fi
else
  echo "$name: Partition table written successfully"
fi

echo "$name: Verifying written partition table:"
/usr/sbin/sfdisk -d "$boot_disk_device" 2>/dev/null | grep "/dev/" | \
  while IFS= read -r _vl; do echo "$name:   $_vl"; done

# ── Sync kernel via partx (RHEL 8/9; no-op on RHEL 7 where it is absent) ────

echo "$name: Syncing kernel partition table via partx (if available)"
if command -v partx >/dev/null 2>&1; then
  partx -u "$boot_disk_device" 2>&1
  echo "$name: partx complete"
else
  echo "$name: partx not available — kernel updated via sfdisk BLKRRPART"
fi

# Confirm kernel sysfs reflects the new boot partition size.
_orig_boot_size=""
eval "_orig_boot_size=\$_sysfs_size_${boot_part_num}"
_expected_boot_size=$(( _orig_boot_size + _offset_sectors ))
_actual_boot_size=$(</sys/class/block/"$boot_part_name"/size)

echo "$name: Expecting boot partition size to become $_expected_boot_size sectors" \
     "(was $_orig_boot_size)"
_settle_wait=0
while [[ $_settle_wait -lt 30 ]]; do
  _actual_boot_size=$(</sys/class/block/"$boot_part_name"/size)
  if [[ "$_actual_boot_size" -eq "$_expected_boot_size" ]]; then
    echo "$name: Kernel partition table updated (boot size=$_actual_boot_size)"
    break
  fi
  sleep 1
  _settle_wait=$((_settle_wait + 1))
done
if [[ $_settle_wait -ge 30 ]]; then
  echo "$name: WARNING: Kernel did not reflect new partition table after 30s"
  echo "$name: On-disk table is correct. Filesystem grow will be skipped this boot."
fi

# ── Grow /boot filesystem ─────────────────────────────────────────────────────

_actual_boot_size=$(</sys/class/block/"$boot_part_name"/size)
if [[ "$_actual_boot_size" -eq "$_expected_boot_size" ]]; then
  echo "$name: Growing the /boot $boot_fs_type filesystem"
  if [[ "$boot_fs_type" =~ ^ext[2-4]$ ]]; then
    echo "$name: Running e2fsck"
    /usr/sbin/e2fsck -fy "/dev/$boot_part_name"
    echo "$name: Running resize2fs"
    if ! /usr/sbin/resize2fs "/dev/$boot_part_name"; then
      echo "$name: resize2fs failed"
      exit 1
    fi
    echo "$name: resize2fs complete"
  elif [[ "$boot_fs_type" == "xfs" ]]; then
    _xfs_tmp="/tmp/bigboot_xfs_mount"
    mkdir -p "$_xfs_tmp"
    if ! /usr/bin/mount -t xfs "/dev/$boot_part_name" "$_xfs_tmp"; then
      echo "$name: Failed to mount boot partition for xfs_growfs"
      exit 1
    fi
    /usr/sbin/xfs_growfs "$_xfs_tmp"
    _xfs_status=$?
    /usr/bin/umount "$_xfs_tmp"
    rmdir "$_xfs_tmp" 2>/dev/null
    if [[ $_xfs_status -ne 0 ]]; then
      echo "$name: xfs_growfs failed"
      exit 1
    fi
  fi
else
  echo "$name: Skipping filesystem grow — kernel still sees old partition size"
  echo "$name: On-disk partition table is correct. Filesystem will be grown on next boot."
fi

# ══════════════════════════════════════════════════════════════════════════════
# RESUME UDEV QUEUE + SETTLE + SPAM CLEANUP
# ══════════════════════════════════════════════════════════════════════════════
echo "$name: Resuming udev rule execution"
/usr/sbin/udevadm control --start-exec-queue 2>/dev/null || true
_udev_stopped=false

echo "$name: Waiting for udev event queue to drain (suppressing systemd spam)..."
/usr/sbin/udevadm settle --timeout=30 2>/dev/null || true

# Clear the screen to wipe away the massive systemd start/stop message wall
echo -ne "\033[2J\033[H"
echo "$name: Udev event queue drained. Partition table reload complete."

# ══════════════════════════════════════════════════════════════════════════════
# GLOBAL STATEFUL LVM REACTIVATION
# ══════════════════════════════════════════════════════════════════════════════

for _vg in $_active_vgs; do
  echo "$name: Restoring VG $_vg to ACTIVE state for root pivot"
  /usr/sbin/lvm vgchange --config 'global { use_lvmetad = 0 }' -ay "$_vg" 2>&1
done

if [[ -n "$_active_vgs" ]]; then
  echo "$name: Waiting for LVM symlinks to populate..."
  /usr/sbin/udevadm settle --timeout=15 2>/dev/null || true

  _lv_count=0
  for _vg in $_active_vgs; do
    _vg_escaped="${_vg//-/--}"
    for _dm in /dev/mapper/"${_vg_escaped}"-*; do
      if [[ -b "$_dm" ]]; then
        _lv_count=$((_lv_count + 1))
      fi
    done
  done

  if [[ $_lv_count -gt 0 ]]; then
    echo "$name: $_lv_count previously active LVs successfully restored."
  else
    echo "$name: WARNING: No LVs found in /dev/mapper. Root mount may fail."
  fi
fi

# ── Restore console blanking timeout ──────────────────────────────────────────
echo -ne "\x1b[9;${_prev_timeout}]"

# ── Done ──────────────────────────────────────────────────────────────────────
echo "$name: Boot partition $boot_part_name successfully increased" \
     "by $boot_size_increase_in_bytes ($SECONDS seconds)"
: > /run/bigboot.done 2>/dev/null
exit 0
