#!/bin/bash
#
# This is the new bigboot reboot script. Unlike the old script, this one
# only deals with the partitioning and boot filesystem changes required.
# The preparations to reduce the LVM physical volume or Btrfs filesystem
# volume are now done in advance by Ansible before rebooting.
#
# This script performs the following steps in this order:
#
# 1. Move the end of the next partition to make it smaller
# 2. Use sfdisk to copy the blocks of the next partition
# 3. Move the end of the boot partition making it bigger
# 4. Grow the boot filesystem
#
# Usage: bigboot.sh boot_partition_name next_partition_name boot_size_increase_in_bytes
#
# For example, this command would increase a /boot filesystem on /dev/sda1 by 500M:
#
# bigboot.sh sda1 sda2 524288000
#

# Get input values
boot_part_name="$1"
next_part_name="$2"
boot_size_increase_in_bytes="$3"

# Validate inputs
name="bigboot"
if [[ ! -b "/dev/$boot_part_name" ]]; then
  echo "$name: Boot partition is not a block device: $boot_part_name"
  exit 1
fi
if [[ ! -b "/dev/$next_part_name" ]]; then
  echo "$name: Next partition is not a block device: $next_part_name"
  exit 1
fi
if [[ ! $boot_size_increase_in_bytes -gt 0 ]]; then
  echo "$name: Invalid size increase value: $boot_size_increase_in_bytes"
  exit 1
fi

# Calculate device and partition details
boot_disk_device=/dev/"$(/usr/bin/basename "$(readlink -f /sys/class/block/"$boot_part_name"/..)")"
boot_part_num="$(</sys/class/block/"$boot_part_name"/partition)"
next_part_num="$(</sys/class/block/"$next_part_name"/partition)"
next_part_start="$(($(</sys/class/block/"$next_part_name"/start)*512))"
next_part_size="$(($(</sys/class/block/"$next_part_name"/size)*512))"
next_part_end="$((next_part_start+next_part_size-1))"
next_part_new_end="$((next_part_end-boot_size_increase_in_bytes))"

# Validate boot filesystem
eval "$(/usr/sbin/blkid /dev/"$boot_part_name" -o udev)"
boot_fs_type="$ID_FS_TYPE"
if [[ ! "$boot_fs_type" =~ ^ext[2-4]$|^xfs$ ]]; then
  echo "$name: Boot filesystem type is not extendable: $boot_fs_type"
  exit 1
fi

# Validate next partition
eval "$(/usr/sbin/blkid /dev/"$next_part_name" -o udev)"
if [[ "$ID_FS_TYPE" == "LVM2_member" ]]; then
  eval "$(/usr/sbin/lvm pvs --noheadings --nameprefixes -o vg_name /dev/"$next_part_name")"
  next_part_vg="$LVM2_VG_NAME"
fi

# Shrink next partition
echo "$name: Shrinking partition $next_part_name by $boot_size_increase_in_bytes"
if ! ret=$(echo Yes | /usr/sbin/parted "$boot_disk_device" ---pretend-input-tty unit B resizepart "$next_part_num" "$next_part_new_end" 2>&1); then 
  echo "$name: Failed shrinking partition $next_part_name: $ret"
  exit 1
fi

# Disable virtual console blanking
prev_timeout="$(($(</sys/module/kernel/parameters/consoleblank)/60))"
echo -ne "\x1b[9;0]"

# Output progress messages to help impatient operators recognize the server is not "hung"
( sleep 9
  while pid="$(ps -C sfdisk -o pid:1=)"; do
    pct='??'
    for fd in /proc/"$pid"/fd/*; do
      if [[ "$(readlink "$fd")" == "$boot_disk_device" ]]; then
        offset="$(awk '/pos:/ {print $2}' /proc/"$pid"/fdinfo/"${fd##*/}")"
        pct="$((-100*offset/next_part_size+100))"
        break
      fi
    done
    echo "$name: Partition move is progressing, please wait! ($pct% complete)"
    sleep 20
  done ) &

# Shift next partition
echo "$name: Moving up partition $next_part_name by $boot_size_increase_in_bytes"
if ! ret=$(echo "+$((boot_size_increase_in_bytes/512))," | /usr/sbin/sfdisk --move-data "$boot_disk_device" -N "$next_part_num" --force 2>&1); then
  echo "$name: Failed moving up partition $next_part_name: $ret"
  exit 1
fi

# Increase boot partition
echo "$name: Increasing boot partition $boot_part_name by $boot_size_increase_in_bytes"
if ! ret=$(echo "- +" | /usr/sbin/sfdisk "$boot_disk_device" -N "$boot_part_num" --no-reread --force 2>&1); then
  echo "$name: Failed increasing boot partition $boot_part_name: $ret"
  exit 1
fi

# Update kernel partition table
echo "$name: Updating kernel partition table"
[[ "$next_part_vg" ]] && /usr/sbin/lvm vgchange -an "$next_part_vg" && sleep 1
/usr/sbin/partprobe "$boot_disk_device" && sleep 1
[[ "$next_part_vg" ]] && /usr/sbin/lvm vgchange -ay "$next_part_vg" && sleep 1

# Grow the /boot filesystem
echo "$name: Growing the /boot $boot_fs_type filesystem"
if [[ "$boot_fs_type" =~ ^ext[2-4]$ ]]; then
  /usr/sbin/e2fsck -fy "/dev/$boot_part_name"
  if ! /usr/sbin/resize2fs "/dev/$boot_part_name"; then
    echo "$name: resize2fs error while growing the /boot filesystem"
    exit 1
  fi
fi
if [[ "$boot_fs_type" == "xfs" ]]; then
  tmp_dir=$(/usr/bin/mktemp -d)
  /usr/bin/mount -t xfs "/dev/$boot_part_name" "$tmp_dir"
  /usr/sbin/xfs_growfs "/dev/$boot_part_name"
  status=$?
  /usr/bin/umount "/dev/$boot_part_name"
  if [[ $status -ne 0 ]]; then
    echo "$name: xfs_growfs error while growing the /boot filesystem"
    exit 1
  fi
fi

# Restore virtual console blanking
echo -ne "\x1b[9;$prev_timeout]"

exit 0
