#!/bin/bash
VOLUME_SIZE_ALIGNMENT=4096

function get_device_name() {
    if [[ "$1" == "UUID="* ]]; then
        dev_name=$( parse_uuid "$1" )
    else
        dev_name=$(/usr/bin/cut -d " " -f 1 <<< "$1")
    fi
    status=$?
    if [[  status -ne 0 ]]; then
        return $status
    fi
    echo "$dev_name"
    return $status
}

function ensure_size_in_bytes() {
    local expected_size
    expected_size=$(/usr/bin/numfmt  --from iec "$1")
    (( expected_size=(expected_size+VOLUME_SIZE_ALIGNMENT)/VOLUME_SIZE_ALIGNMENT*VOLUME_SIZE_ALIGNMENT ))
    echo $expected_size
}

function is_device_mounted() {
    /usr/bin/findmnt --source "$1" 1>&2>/dev/null
    status=$?
    if [[  status -eq 0 ]]; then
        echo "Device $1 is mounted" >&2
        return 1
    fi
    return 0
}

function get_current_volume_size() {
    val=$(/usr/bin/lsblk -b "$1" -o SIZE --noheadings)
    status=$?
    if [[ $status -ne 0 ]]; then
        return $status
    fi
    echo "$val"
    return 0
}

function is_lvm(){
    val=$( /usr/bin/lsblk "$1" --noheadings -o TYPE 2>&1)
    status=$?
    if [[ status -ne 0 ]]; then
        echo "Failed to list block device properties for $2: $val" >&2
        return 1
    fi
    if [[ "$val" != "lvm"  ]]; then
        echo "Device $device_name is not of lvm type" >&2
        return 1
    fi
    return 0
}

function parse_uuid() {
    uuid=$(/usr/bin/awk '{print $1}'<<< "$1"|/usr/bin/awk -F'UUID=' '{print $2}')
    val=$(/usr/bin/lsblk /dev/disk/by-uuid/"$uuid" -o NAME --noheadings 2>/dev/null)
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Failed to retrieve device name for UUID=$uuid" >&2
        return $status
    fi
    echo "/dev/mapper/$val"
    return 0
}

function shrink_volume() {
    /usr/sbin/lvm lvreduce --resizefs -L "$2b" "$1"
    return $?
}

function check_volume_size() {
    current_size=$(get_current_volume_size "$1")
    if [[ $current_size -lt $2 ]];then
        echo "Current volume size for device $1 ($current_size bytes) is lower to expected $2 bytes" >&2
        return 1
    fi
    if [[ $current_size -eq $2 ]]; then
        echo "Current volume size for device $1 already equals $2 bytes" >&2
        return 1
    fi
    return $?
}

function convert_size_to_fs_blocks(){
    local device=$1
    local size=$2
    block_size_in_bytes=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block size:/{print $3}')
    echo $(( size / block_size_in_bytes ))
}

function calculate_expected_resized_file_system_size_in_blocks(){
    local device=$1
    increment_boot_partition_in_blocks=$(convert_size_to_fs_blocks "$device" "$INCREMENT_BOOT_PARTITION_SIZE_IN_BYTES")
    total_block_count=$(/usr/sbin/tune2fs -l "$device" | /usr/bin/awk '/Block count:/{print $3}')
    new_fs_size_in_blocks=$(( total_block_count - increment_boot_partition_in_blocks ))
    echo $new_fs_size_in_blocks
}

function check_filesystem_size() {
    local device=$1
    local new_fs_size_in_blocks=$2
    new_fs_size_in_blocks=$(calculate_expected_resized_file_system_size_in_blocks "$device")
# it is possible that running this command after resizing it might give an even smaller number.
    minimum_blocks_required=$(/usr/sbin/resize2fs -P "$device" 2> /dev/null | /usr/bin/awk  '{print $NF}')

    if [[ "$new_fs_size_in_blocks" -le "0" ]]; then
        echo "Unable to shrink volume: New size is 0 blocks"
        return 1
    fi
        if [[ $minimum_blocks_required -gt $new_fs_size_in_blocks ]]; then
        echo "Unable to shrink volume: Estimated minimum size of the file system $1 ($minimum_blocks_required blocks) is greater than the new size $new_fs_size_in_blocks blocks" >&2
        return 1
    fi
    return 0
}

function process_entry() {
    is_lvm "$1" "$3"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    expected_size_in_bytes=$(ensure_size_in_bytes "$2")
    check_filesystem_size "$1" "$expected_size_in_bytes"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    check_volume_size "$1" "$expected_size_in_bytes"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    is_device_mounted "$1"
    status=$?
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    shrink_volume "$1" "$expected_size_in_bytes"
    return $?
}

function display_help() {
    echo "Program to shrink ext4 file systems hosted in Logical Volumes.

    Usage: '$(basename "$0")' [-h] [-d=|--device=]

    Example:

    where:
        -h show this help text
        -d|--device= name or UUID of the device that holds an ext4 and the new size separated by a ':'
                     for example /dev/my_group/my_vol:2G
                     Sizes will be rounded to be 4K size aligned"
}

function parse_flags() {
    for i in "$@"
        do
        case $i in
            -d=*|--device=*)
            entries+=("${i#*=}")
            ;;
            -h)
            display_help
            exit 0
            ;;
            *)
            # unknown option
            echo "Unknown flag $i"
            display_help
            exit 1
            ;;
        esac
    done
    if [[ ${#entries[@]} == 0 ]]; then
        display_help
        exit 0
    fi
}

function parse_entry() {
    IFS=':'
    read -ra strarr <<< "$1"

    if [[ ${#strarr[@]} != 2 ]]; then
        echo "Invalid device entry $1"
        display_help
        return 1
    fi

    device="${strarr[0]}"
    expected_size="${strarr[1]}"
}

function main() {

    local -a entries=()
    local run_status=0

    parse_flags "$@"

    for entry in "${entries[@]}"
    do
        local device
        local expected_size
        parse_entry "$entry"
        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
            continue
        fi
        device_name=$( get_device_name "$device" )
        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
            continue
        fi

        process_entry "$device_name" "$expected_size" "$device"

        status=$?
        if [[ $status -ne 0 ]]; then
            run_status=$status
        fi
    done

    exit $run_status
}

main "$@"
