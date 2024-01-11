#!/bin/bash

# Command parameters
INCREMENT_BOOT_PARTITION_SIZE=
DEVICE_NAME=
BOOT_PARTITION_NUMBER=
PARTITION_PREFIX=

# Script parameters
ADJACENT_PARTITION_NUMBER=
BOOT_FS_TYPE=
EXTENDED_PARTITION_TYPE=extended
LOGICAL_VOLUME_DEVICE_NAME=
INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES=
SHRINK_SIZE_IN_BYTES=

print_help(){
    echo "Usage: $(basename "$0") -d=<device_name> -s=<increase_size_with_units> -b=<boot_partition_number> -p=<partition_prefix>"
}

get_device_type(){
    local device=$1
    val=$(/usr/bin/lsblk "$device" -o type --noheadings 2>&1)
    local status=$?
    if [[ status -ne 0 ]]; then
        echo "Failed to retrieve device type for $device: $val"
        exit 1
    fi
    type=$(tail -n1 <<<"$val")
    if [[ -z $type ]]; then
        echo "Unknown device type for $device"
        exit 1
    fi
    echo "$type"
}

ensure_device_not_mounted() {
    local device=$1
    local devices_to_check
    device_type=$(get_device_type "$device")
    if [[ $device_type == "lvm" ]]; then
        # It's an LVM block device
        # Capture the LV device names. Since we'll have to shift the partition, we need to make sure all LVs are not mounted in the adjacent partition.
        devices_to_check=$(/usr/sbin/lvm pvdisplay "$device" -m |/usr/bin/grep "Logical volume" |/usr/bin/awk '{print $3}')
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

get_fs_type(){
    local device=$1
    ret=$(/usr/sbin/blkid "$device" -o udev | sed -n -e 's/ID_FS_TYPE=//p' 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        exit $status
    fi
    echo "$ret"
}

ensure_extendable_fs_type(){
    local device=$1
    ret=$(get_fs_type "$device")
    if [[ "$ret" != "ext4" ]] && [[ "$ret" != "xfs" ]]; then
        echo "Boot file system type $ret is not extendable"
        exit 1
    fi
    BOOT_FS_TYPE=$ret
}

get_successive_partition_number() {
    boot_line_number=$(/usr/sbin/parted -m "$DEVICE_NAME" print |/usr/bin/sed -n '/^'"$BOOT_PARTITION_NUMBER"':/ {=}')
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
    EXTENDED_PARTITION_NUMBER=$(/usr/sbin/parted "$DEVICE_NAME" print | /usr/bin/sed -n '/'"$EXTENDED_PARTITION_TYPE"'/p'|awk '{print $1}')
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
      # if there's an extended partition, use the last one as the target partition to shrink
      ADJACENT_PARTITION_NUMBER=$(/usr/sbin/parted "$DEVICE_NAME" print |grep -v "^$" |awk 'END{print$1}')
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

init_variables(){
    parse_flags "$@"
    validate_parameters
    get_successive_partition_number
}

check_filesystem(){
    local device=$1
    fstype=$(get_fs_type "$device")
    if [[ "$fstype" == "swap" ]]; then
     echo "Warning: cannot run fsck to a swap partition for $device"
     return 0
    fi
    if [[ "$BOOT_FS_TYPE" == "ext4" ]]; then
        # Retrieve the estimated minimum size in bytes that the device can be shrank
        ret=$(/usr/sbin/e2fsck -fy "$device" 2>&1)
        local status=$?
        if [[ status -ne 0 ]]; then
            echo "Warning: File system check failed for $device: $ret"
        fi
    fi
}

convert_size_to_fs_blocks(){
    local device=$1
    local size=$2
    block_size_in_bytes=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block size:/{print $3}')
    echo $(( size / block_size_in_bytes ))
}

calculate_expected_resized_file_system_size_in_blocks(){
    local device=$1
    increment_boot_partition_in_blocks=$(convert_size_to_fs_blocks "$device" "$INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES")
    total_block_count=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block count:/{print $3}')
    new_fs_size_in_blocks=$(( total_block_count - increment_boot_partition_in_blocks ))
    echo $new_fs_size_in_blocks
}

get_free_device_size() {
    free_space=$(/usr/sbin/parted -m "$DEVICE_NAME" unit b print free | /usr/bin/awk -F':'  '/'"^$ADJACENT_PARTITION_NUMBER:"'/{getline;print $0}'|awk -F':' '/free/{print $4}'|sed -e 's/B//g')
    echo "$free_space"
}

get_volume_group_name(){
    local volume_group_name
    ret=$(/usr/sbin/lvm pvs "${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}" -o vg_name --noheadings|/usr/bin/sed 's/^[[:space:]]*//g')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to retrieve volume group name for logical volume $LOGICAL_VOLUME_DEVICE_NAME: $ret"
        exit $status
    fi
    echo "$ret"
}

deactivate_volume_group(){
    local volume_group_name
    volume_group_name=$(get_volume_group_name)
    ret=$(/usr/sbin/lvm vgchange -an "$volume_group_name" 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to deactivate volume group $volume_group_name: $ret"
        exit $status
    fi
    # avoid potential deadlocks with udev rules before continuing
    sleep 1
}

check_available_free_space(){
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    free_device_space_in_bytes=$(get_free_device_size)
    # if there is enough free space after the adjacent partition, there is no need to shrink it.
    if [[ $free_device_space_in_bytes -gt $INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES ]]; then
        SHRINK_SIZE_IN_BYTES=0
        return
    fi
    SHRINK_SIZE_IN_BYTES=$((INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES-free_device_space_in_bytes))
    device_type=$(get_device_type "${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}")
    if [[ "$device_type" == "lvm" ]]; then
        # there is not enough free space after the adjacent partition, calculate how much extra space is needed
        # to be fred from the PV
        local volume_group_name
        volume_group_name=$(get_volume_group_name)
        pe_size_in_bytes=$(/usr/sbin/lvm pvdisplay "$device" --units b| /usr/bin/awk 'index($0,"PE Size") {print $3}')
        unusable_space_in_pv_in_bytes=$(/usr/sbin/lvm pvdisplay --units B "$device" | /usr/bin/awk 'index($0,"not usable") {print $(NF-1)}'|/usr/bin/numfmt --from=iec)
        total_pe_count_in_vg=$(/usr/sbin/lvm vgs "$volume_group_name" -o pv_pe_count --noheadings)
        allocated_pe_count_in_vg=$(vgs "$volume_group_name" -o pv_pe_alloc_count --noheadings)
        free_pe_count=$((total_pe_count_in_vg - allocated_pe_count_in_vg))
        # factor in the unusable space to match the required number of free PEs
        required_pe_count=$(((SHRINK_SIZE_IN_BYTES+unusable_space_in_pv_in_bytes)/pe_size_in_bytes))
        if [[ $required_pe_count -gt $free_pe_count ]]; then
            echo "Not enough available free PE in VG $volume_group_name: Required $required_pe_count but found $free_pe_count"
            exit 1
        fi
    fi
}

resolve_device_name(){
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    device_type=$(get_device_type "$device")
    if [[ $device_type == "lvm" ]]; then
        # It's an LVM block device
        # Determine which is the last LV in the PV
        # shellcheck disable=SC2016
        device=$(/usr/sbin/lvm pvdisplay "$device" -m | /usr/bin/sed  -n '/Logical volume/h; ${x;p;}' | /usr/bin/awk  '{print $3}')
        status=$?
        if [[ status -ne 0 ]]; then
            echo "Failed to identify the last LV in $device"
            exit $status
        fi
        # Capture the LV device name
        LOGICAL_VOLUME_DEVICE_NAME=$device
    fi
}

check_device(){
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
        echo "Failed to move PEs in PV $LOGICAL_VOLUME_DEVICE_NAME: $ret"
        exit $status
    fi
    check_filesystem "$LOGICAL_VOLUME_DEVICE_NAME"
}

shrink_physical_volume() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    pe_size_in_bytes=$(/usr/sbin/lvm pvdisplay "$device" --units b| /usr/bin/awk 'index($0,"PE Size") {print $3}')
    unusable_space_in_pv_in_bytes=$(/usr/sbin/lvm pvdisplay --units B "$device" | /usr/bin/awk 'index($0,"not usable") {print $(NF-1)}'|/usr/bin/numfmt --from=iec)

    total_pe_count=$(/usr/sbin/lvm pvs "$device" -o pv_pe_count --noheadings | /usr/bin/sed 's/^[[:space:]]*//g')
    evict_size_in_PE=$((SHRINK_SIZE_IN_BYTES/pe_size_in_bytes))
    shrink_start_PE=$((total_pe_count - evict_size_in_PE))
    pv_new_size_in_bytes=$(( (shrink_start_PE*pe_size_in_bytes) + unusable_space_in_pv_in_bytes ))

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
    check_filesystem "$LOGICAL_VOLUME_DEVICE_NAME"
}

calculate_new_end_partition_size_in_bytes(){
    local partition_number=$1
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${partition_number}"
    current_partition_size_in_bytes=$(/usr/sbin/parted -m "$DEVICE_NAME" unit b print| /usr/bin/awk '/^'"$partition_number"':/ {split($0,value,":"); print value[3]}'| /usr/bin/sed -e's/B//g')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to convert new device size to megabytes $device: $ret"
        exit 1
    fi

    new_partition_size_in_bytes=$(( current_partition_size_in_bytes - SHRINK_SIZE_IN_BYTES))
    echo "$new_partition_size_in_bytes"
}

shrink_partition() {
    local partition_number=$1
    new_end_partition_size_in_bytes=$(calculate_new_end_partition_size_in_bytes "$partition_number")
    echo "Shrinking partition $partition_number in $DEVICE_NAME" >&2
    ret=$(echo Yes | /usr/sbin/parted "$DEVICE_NAME" ---pretend-input-tty unit B resizepart "$partition_number" "$new_end_partition_size_in_bytes" 2>&1 )
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to resize device $DEVICE_NAME$partition_number to size: $ret"
        exit 1
    fi
}

shrink_adjacent_partition(){
    if [[ $SHRINK_SIZE_IN_BYTES -eq 0 ]]; then
        # no need to shrink the PV or the partition as there is already enough free available space after the partition holding the PV
        return 0
    fi
    local device_type
    device_type=$(get_device_type "${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}")
    if [[ "$device_type" == "lvm" ]]; then
        shrink_physical_volume
    fi
    shrink_partition "$ADJACENT_PARTITION_NUMBER"
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
        # resize the extended partition
        shrink_partition "$EXTENDED_PARTITION_NUMBER"
    fi
}

shift_adjacent_partition() {
    # If boot partition is not the last one, shift the successive partition to the right to take advantage of the newly fred space. Use 'echo '<amount_to_shift>,' | sfdisk --move-data <device name> -N <partition number>
    # to shift the partition to the right.
    # The astute eye will notice that we're moving the partition, not the last logical volume in the partition.
    local target_partition=$ADJACENT_PARTITION_NUMBER
    if [[ -n "$EXTENDED_PARTITION_NUMBER" ]]; then
        target_partition=$EXTENDED_PARTITION_NUMBER
    fi
    echo "Moving up partition $target_partition in $DEVICE_NAME by $INCREMENT_BOOT_PARTITION_SIZE" >&2
    ret=$(echo "+$INCREMENT_BOOT_PARTITION_SIZE,"| /usr/sbin/sfdisk --move-data "$DEVICE_NAME" -N "$target_partition" --force 2>&1)
    status=$?
    if [[ status -ne 0 ]]; then
        echo "Failed to shift partition '$DEVICE_NAME$target_partition': $ret"
        exit $status
    fi
}

update_kernel_partition_tables(){
    # Ensure no size inconsistencies between PV and partition
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    device_type=$(get_device_type "$device")
    if [[ $device_type == "lvm" ]]; then
        ret=$(/usr/sbin/lvm pvresize "$device" -y 2>&1)
        status=$?
        if [[ status -ne 0 ]]; then
            echo "Failed to align PV and partition sizes '$device': $ret"
            exit $status
        fi
        # ensure that the VG is not active so that the changes to the kernel PT are reflected by the partprobe command
        deactivate_volume_group
    fi
    /usr/sbin/partprobe "$DEVICE_NAME" 2>&1
    if [[ $device_type == "lvm" ]]; then
        # reactivate volume group
        activate_volume_group
    fi
}

increase_boot_partition() {
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${BOOT_PARTITION_NUMBER}"
    local new_fs_size_in_blocks=
    echo "Increasing boot partition $BOOT_PARTITION_NUMBER in $DEVICE_NAME by $INCREMENT_BOOT_PARTITION_SIZE" >&2
    ret=$(echo "- +"| /usr/sbin/sfdisk "$DEVICE_NAME" -N "$BOOT_PARTITION_NUMBER" --no-reread --force 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to shift boot partition '$device': $ret"
        return
    fi
    update_kernel_partition_tables
    # Extend the boot file system with `resize2fs <boot_partition>`
    if [[ "$BOOT_FS_TYPE" == "ext4" ]]; then
        check_filesystem "$device"
        increment_boot_partition_in_blocks=$(convert_size_to_fs_blocks "$device" "$INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES")
        total_block_count=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block count:/{print $3}')
        new_fs_size_in_blocks=$(( total_block_count + increment_boot_partition_in_blocks ))
        ret=$(/usr/sbin/resize2fs "$device" $new_fs_size_in_blocks 2>&1)
    elif [[ "$BOOT_FS_TYPE" == "xfs" ]]; then
        block_size_in_bytes=$(/usr/sbin/xfs_db "$device" -c "sb" -c "print blocksize" |/usr/bin/awk '{print $3}')
        current_blocks_in_data=$(/usr/sbin/xfs_db "$device" -c "sb" -c "print dblocks" |/usr/bin/awk '{print $3}')
        increment_boot_partition_in_blocks=$((INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES/block_size_in_bytes))
        new_fs_size_in_blocks=$((current_blocks_in_data + increment_boot_partition_in_blocks))
        # xfs_growfs requires the file system to be mounted in order to change its size
        # Create a temporal directory
        tmp_dir=$(/usr/bin/mktemp -d)
        # Mount the boot file system in the temporal directory
        /usr/bin/mount "$device" "$tmp_dir"
        ret=$(/usr/sbin/xfs_growfs "$device" -D "$new_fs_size_in_blocks" 2>&1)
        # Capture the status
        status=$?
        # Unmount the file system
        /usr/bin/umount "$device"
    else
        echo "Device $device does not contain an ext4 or xfs file system: $BOOT_FS_TYPE"
        return
    fi
        status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to resize boot partition '$device': $ret"
        return
    fi
    echo "Boot file system increased to $new_fs_size_in_blocks blocks" >&2
}

activate_volume_group(){
    local device="${DEVICE_NAME}${PARTITION_PREFIX}${ADJACENT_PARTITION_NUMBER}"
    local volume_group_name
    volume_group_name=$(get_volume_group_name)
    ret=$(/usr/sbin/lvm vgchange -ay "$volume_group_name" 2>&1)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to activate volume group $volume_group_name: $ret"
        exit $status
    fi
    # avoid potential deadlocks with udev rules before continuing
    sleep 1
}

# last steps are to run the fsck on boot partition and activate the volume group if necessary
cleanup(){
    # run a file system check to the boot file system
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
