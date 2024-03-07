#!/bin/bash
#
# Script to increase the ext/xfs boot partition in a BIOS system by shifting
# the adjacent partition to the boot partition by the parametrized size. It
# expects the device to have enough free space to shift to the right of the
# adjacent partition, that is towards the end of the device. It only works
# with ext and xfs filesystems and supports adjacent partitions as primary
# or logical partitions and LVM in the partition.
#
# The parametrized size supports M for MiB and G for GiB. If no units is given,
# it is interpreted as bytes
#
# Usage: bigboot.sh -d=<device_name> -s=<increase_size_with_units> -b=<boot_partition_number> -p=<partition_prefix>
#
# Example
#  Given this device partition:
#    Number  Start   End     Size    Type      File system  Flags
#            32.3kB  1049kB  1016kB            Free Space
#    1       1049kB  11.1GB  11.1GB  primary   ext4         boot
#    2       11.1GB  32.2GB  21.1GB  extended
#    5       11.1GB  32.2GB  21.1GB  logical   ext4
#
#  Running the command:
#    $>bigboot.sh -d=/dev/sda -s=1G -b=1
#
#  Will increase the boot partition in /dev/vdb by 1G and shift the adjacent
#  partition in the device by the equal amount.
#
#    Number  Start   End     Size    Type      File system  Flags
#            32.3kB  1049kB  1016kB            Free Space
#    1       1049kB  12.2GB  12.2GB  primary   ext4         boot
#    2       12.2GB  32.2GB  20.0GB  extended
#    5       12.2GB  32.2GB  20.0GB  logical   ext4
#

# Command parameters
INCREMENT_BOOT_PARTITION_SIZE=
DEVICE_NAME=
BOOT_PARTITION_NUMBER=
PARTITION_PREFIX=

# Script parameters
ADJACENT_PARTITION_NUMBER=
BOOT_FS_TYPE=
EXTENDED_PARTITION_TYPE=extended
INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES=
SHRINK_SIZE_IN_BYTES=

print_help() {
    echo "Usage: $(basename "$0") -d=<device_name> -s=<increase_size_with_units> -b=<boot_partition_number> -p=<partition_prefix>"
}

get_device_type() {
    local device=$1
    if /usr/sbin/lvm pvs "$device" > /dev/null 2>&1; then
        echo "lvm"
    else
        echo "other"
    fi
}

ensure_device_not_mounted() {
    local device=$1
    local devices_to_check
    device_type=$(get_device_type "$device")
    if [[ $device_type == "lvm" ]]; then
        # It's an LVM block device
        # Capture the LV device names. Since we'll have to shift the partition, we need to make sure all LVs are not mounted in the adjacent partition.
        devices_to_check=$(/usr/sbin/lvm pvdisplay "$device" -m | /usr/bin/grep "Logical volume" | /usr/bin/awk '{print $3}')
    else
        # Use the device and partition number instead
        devices_to_check=$device
    fi
    for device_name in $devices_to_check; do
        /usr/bin/findmnt --source "$device_name" 1>&2>/dev/null
        status=$?
        if [[  status -eq 0 ]]; then
            echo "Device $device_name is mounted"
            exit 1
        fi
    done
}

validate_device() {
    local device=$1
    if [[ -z "${device}" ]]; then
        echo "Missing device name"
        print_help
        exit 1
    fi
    if [[ ! -e "${device}" ]]; then
        echo "Device ${device} not found"
        exit 1
    fi
    ret=$(/usr/sbin/fdisk -l "${device}" 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to open device ${device}: $ret"
        exit 1
    fi
}

validate_increment_partition_size() {
    if [[ -z "$INCREMENT_BOOT_PARTITION_SIZE" ]]; then
        echo "Missing incremental size for boot partition"
        print_help
        exit 1
    fi
    ret=$(/usr/bin/numfmt --from=iec "$INCREMENT_BOOT_PARTITION_SIZE" 2>&1)
    status=$?
     if [[ $status -ne 0 ]]; then
        echo "Invalid size value for '$INCREMENT_BOOT_PARTITION_SIZE': $ret"
        exit $status
    fi
    INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES=$ret
}

# Capture all parameters:
# Mandatory: Device, Size and Boot Partition Number
# Optional: Partition Prefix (e.g. "p" for nvme based volumes)
parse_flags() {
    for i in "$@"
        do
        case $i in
            -d=*|--device=*)
            DEVICE_NAME="${i#*=}"
            ;;
            -s=*|--size=*)
            INCREMENT_BOOT_PARTITION_SIZE="${i#*=}"
            ;;
            -b=*|--boot=*)
            BOOT_PARTITION_NUMBER="${i#*=}"
            ;;
            -p=*|--prefix=*)
            PARTITION_PREFIX="${i#*=}"
            ;;
            -h)
            print_help
            exit 0
            ;;
            *)
            # unknown option
            echo "Unknown flag $i"
            print_help
            exit 1
            ;;
        esac
    done
}

validate_parameters() {
    validate_device "${DEVICE_NAME}"
    validate_increment_partition_size

    # Make sure BOOT_PARTITION_NUMBER is set to avoid passing only DEVICE_NAME
    if [[ -z "$BOOT_PARTITION_NUMBER" ]]; then
        echo "Boot partition number was not set"
        print_help
        exit 1
    fi
    validate_device "${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"

    ensure_device_not_mounted "${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"
    ensure_extendable_fs_type "${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"
}

get_fs_type() {
    local device=$1
    ret=$(/usr/sbin/blkid "$device" -o udev | sed -n -e 's/ID_FS_TYPE=//p' 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        exit $status
    fi
    echo "$ret"
}

ensure_extendable_fs_type() {
    local device=$1
    ret=$(get_fs_type "$device")
    if [[ ! "$ret" =~ ^ext[2-4]$|^xfs$ ]]; then
        echo "Boot filesystem type $ret is not extendable"
        exit 1
    fi
    BOOT_FS_TYPE=$ret
}

get_successive_partition_number() {
    boot_line_number=$(/usr/sbin/parted -m "$DEVICE_NAME" print | /usr/bin/sed -n '/^'"$BOOT_PARTITION_NUMBER"':/ {=}')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Unable to identify boot partition number for '$DEVICE_NAME'"
        exit $status
    fi
    if [[ -z "$boot_line_number" ]]; then
        echo "No boot partition found"
        exit 1
    fi
    # get the extended partition number in case there is one, we will need to shrink it as well
    EXTENDED_PARTITION_NUMBER=$(/usr/sbin/parted "$DEVICE_NAME" print | /usr/bin/sed -n '/'"$EXTENDED_PARTITION_TYPE"'/p' | awk '{print $1}')
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
      # if there's an extended partition, use the last one as the target partition to shrink
      ADJACENT_PARTITION_NUMBER=$(/usr/sbin/parted "$DEVICE_NAME" print | grep -v "^$" | awk 'END{print$1}')
    else
        # get the partition number from the next line after the boot partition
        ADJACENT_PARTITION_NUMBER=$(/usr/sbin/parted -m "$DEVICE_NAME" print | /usr/bin/awk -F ':' '/'"^$BOOT_PARTITION_NUMBER:"'/{getline;print $1}')
    fi
    if ! [[ $ADJACENT_PARTITION_NUMBER == +([[:digit:]]) ]]; then
        echo "Invalid successive partition number '$ADJACENT_PARTITION_NUMBER'"
        exit 1
    fi
    ensure_device_not_mounted "${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
}

init_variables() {
    parse_flags "$@"
    validate_parameters
    get_successive_partition_number
}

check_filesystem() {
    local device=$1
    fstype=$(get_fs_type "$device")
    if [[ "$fstype" == "swap" ]]; then
     echo "Warning: cannot run fsck to a swap partition for $device"
     return 0
    fi
    if [[ "$BOOT_FS_TYPE" =~ ^ext[2-4] ]]; then
        # Retrieve the estimated minimum size in bytes that the device can be shrank
        ret=$(/usr/sbin/e2fsck -fy "$device" 2>&1)
        local status=$?
        if [[ status -ne 0 ]]; then
            echo "Warning: Filesystem check failed for $device: $ret"
        fi
    fi
}

convert_size_to_fs_blocks() {
    local device=$1
    local size=$2
    block_size_in_bytes=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block size:/{print $3}')
    echo $(( size / block_size_in_bytes ))
}

deactivate_volume_group() {
    ret=$(/usr/sbin/lvm vgchange -an "$LVM2_VG_NAME" 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to deactivate volume group $LVM2_VG_NAME: $ret"
        exit $status
    fi
    # avoid potential deadlocks with udev rules before continuing
    sleep 1
}

check_available_free_space() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    # Get LVM details
    eval "$(/usr/sbin/lvm pvs --noheadings --nameprefixes --nosuffix --units b -o vg_name,vg_extent_size,pv_pe_count,pv_pe_alloc_count,vg_free_count "$device")"
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed getting LVM details for $device: $status"
        exit $status
    fi
    # Make shrink size a multiple of extent size
    SHRINK_SIZE_IN_BYTES=$((INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES/LVM2_VG_EXTENT_SIZE*LVM2_VG_EXTENT_SIZE))
    if [[ $INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES -ne $SHRINK_SIZE_IN_BYTES ]]; then
        echo "Requested size increase rounded down to nearest extent multiple." >&2
        INCREMENT_BOOT_PARTITION_SIZE="$(numfmt --to=iec $SHRINK_SIZE_IN_BYTES)"
    fi
    # Quit if shrink size is zero
    if [[ $SHRINK_SIZE_IN_BYTES -le 0 ]]; then
        echo "Boot size increase is $SHRINK_SIZE_IN_BYTES after rounding down to nearest extent multiple. Nothing to do."
        exit 1
    fi
    # Calculate free extents required
    required_pe_count=$((SHRINK_SIZE_IN_BYTES/LVM2_VG_EXTENT_SIZE))
    if [[ $required_pe_count -gt $LVM2_VG_FREE_COUNT ]]; then
        echo "Not enough available free PE in VG $LVM2_VG_NAME: Required $required_pe_count but found $LVM2_VG_FREE_COUNT"
        exit 1
    fi
}

resolve_device_name() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    device_type=$(get_device_type "$device")
    if [[ $device_type != "lvm" ]]; then
        echo "Next partition after /boot is not LVM: $device is type $device_type"
        exit 1
    fi
}

check_device() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    resolve_device_name
    ensure_device_not_mounted "$device"
    check_available_free_space
}

evict_end_PV() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    local shrinking_start_PE=$1
    ret=$(/usr/sbin/lvm pvmove --alloc anywhere "$device":"$shrinking_start_PE"-  2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to evict PEs in PV $device: $ret"
        exit $status
    fi
}

shrink_physical_volume() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    partition_size_in_bytes=$(/usr/sbin/parted -m "$DEVICE_NAME" unit b print | /usr/bin/awk '/^'"$ADJACENT_PARTITION_NUMBER"':/ {split($0,value,":"); print value[4]}' | /usr/bin/sed -e's/B//g')
    pv_new_size_in_bytes=$((partition_size_in_bytes-SHRINK_SIZE_IN_BYTES))
    shrink_start_PE=$((LVM2_PV_PE_COUNT-1-(SHRINK_SIZE_IN_BYTES/LVM2_VG_EXTENT_SIZE)))
    # Test mode pvresize
    ret=$(/usr/sbin/lvm pvresize --setphysicalvolumesize "$pv_new_size_in_bytes"B -t "$device" -y 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        if [[ $status -eq 5 ]]; then
            # ERRNO 5 is equivalent to command failed: https://github.com/lvmteam/lvm2/blob/2eb34edeba8ffc9e22b6533e9cb20e0b5e93606b/tools/errors.h#L23
            # Try to recover by evicting the ending PEs elsewhere in the PV, in case it's a failure due to ending PE's being inside the shrinking area.
            evict_end_PV $shrink_start_PE
        else
            echo "Failed to resize PV $device: $ret"
            exit $status
        fi
    fi
    echo "Shrinking PV $device to $pv_new_size_in_bytes bytes" >&2
    ret=$(/usr/sbin/lvm pvresize --setphysicalvolumesize "$pv_new_size_in_bytes"B "$device" -y 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
            echo "Failed to resize PV $device during retry: $ret"
            exit $status
    fi
}

calculate_new_end_partition_in_bytes() {
    local partition_number=$1
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${partition_number}"
    current_end=$(/usr/sbin/parted -m "$DEVICE_NAME" unit b print | /usr/bin/awk '/^'"$partition_number"':/ {split($0,value,":"); print value[3]}' | /usr/bin/sed -e's/B//g')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to get new end partition size in bytes for $device: $ret"
        exit 1
    fi

    new_end=$((current_end-SHRINK_SIZE_IN_BYTES))
    echo "$new_end"
}

shrink_partition() {
    local partition_number=$1
    new_end_partition_in_bytes=$(calculate_new_end_partition_in_bytes "$partition_number")
    echo "Shrinking partition $partition_number in $DEVICE_NAME by $INCREMENT_BOOT_PARTITION_SIZE" >&2
    ret=$(echo Yes | /usr/sbin/parted "$DEVICE_NAME" ---pretend-input-tty unit B resizepart "$partition_number" "$new_end_partition_in_bytes" 2>&1 )
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to resize device $DEVICE_NAME$partition_number to size: $ret"
        exit 1
    fi
}

shrink_adjacent_partition() {
    shrink_physical_volume
    shrink_partition "$ADJACENT_PARTITION_NUMBER"
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
        # resize the extended partition
        shrink_partition "$EXTENDED_PARTITION_NUMBER"
    fi
}

shift_adjacent_partition() {
    # Move the partition following boot up to make room for increasing the boot partition
    local target_partition=$ADJACENT_PARTITION_NUMBER
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
        target_partition=$EXTENDED_PARTITION_NUMBER
    fi
    # Output progress messages to help impatient operators recognize the server is not "hung"
    ( sleep 4
      while t="$(ps -C sfdisk -o cputime=)"; do
        echo "Bigboot partition move is progressing, please wait! ($t)" >&2
        sleep 120
      done ) &
    echo "Moving up partition $target_partition in $DEVICE_NAME by $INCREMENT_BOOT_PARTITION_SIZE" >&2
    # Default units for sfdisk are 512 byte sectors
    sectors_to_move_up_count=$((SHRINK_SIZE_IN_BYTES/512))
    ret=$(echo "+$sectors_to_move_up_count," | /usr/sbin/sfdisk --move-data "$DEVICE_NAME" -N "$target_partition" --force 2>&1)
    status=$?
    if [[ status -ne 0 ]]; then
        echo "Failed to shift $DEVICE_NAME partition $target_partition up $sectors_to_move_up_count sectors': $ret"
        exit $status
    fi
}

update_kernel_partition_tables() {
    # ensure that the VG is not active so that the changes to the kernel PT are reflected by the partprobe command
    deactivate_volume_group
    /usr/sbin/partprobe "$DEVICE_NAME" 2>&1
    sleep 1
    activate_volume_group
}

increase_boot_partition() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"
    echo "Increasing boot partition $BOOT_PARTITION_NUMBER in $DEVICE_NAME by $INCREMENT_BOOT_PARTITION_SIZE" >&2
    ret=$(echo "- +" | /usr/sbin/sfdisk "$DEVICE_NAME" -N "$BOOT_PARTITION_NUMBER" --no-reread --force 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to increase boot partition '$device': $ret"
        return
    fi
    update_kernel_partition_tables
    # Increase the /boot filesystem
    if [[ "$BOOT_FS_TYPE" =~ ^ext[2-4] ]]; then
        check_filesystem "$device"
        ret=$(/usr/sbin/resize2fs "$device" 2>&1)
        # Capture the status
        status=$?
    elif [[ "$BOOT_FS_TYPE" == "xfs" ]]; then
        # xfs_growfs requires the filesystem to be mounted in order to change its size
        # Create a temporal directory
        tmp_dir=$(/usr/bin/mktemp -d)
        # Mount the boot filesystem in the temporal directory
        /usr/bin/mount "$device" "$tmp_dir"
        ret=$(/usr/sbin/xfs_growfs "$device" 2>&1)
        # Capture the status
        status=$?
        # Unmount the filesystem
        /usr/bin/umount "$device"
    else
        echo "Device $device does not contain an ext4 or xfs filesystem: $BOOT_FS_TYPE"
        status=1
    fi
    if [[ $status -ne 0 ]]; then
        echo "Failed to resize boot partition '$device': $ret"
        return
    fi
    echo "Boot filesystem increased by $INCREMENT_BOOT_PARTITION_SIZE" >&2
}

activate_volume_group() {
    ret=$(/usr/sbin/lvm vgchange -ay "$LVM2_VG_NAME" 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to activate volume group $LVM2_VG_NAME: $ret"
        exit $status
    fi
    # avoid potential deadlocks with udev rules before continuing
    sleep 1
}

# last steps are to run the fsck on boot partition and activate the volume group if necessary
cleanup() {
    # run a filesystem check to the boot filesystem
    check_filesystem "${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"
}

main() {
    init_variables "$@"
    check_device
    shrink_adjacent_partition
    shift_adjacent_partition
    increase_boot_partition
    cleanup
}

main "$@"
