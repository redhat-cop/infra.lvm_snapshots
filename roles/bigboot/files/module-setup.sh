#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

check(){
    return 0
}

install() {
    inst_multiple -o /usr/bin/mount /usr/bin/umount /usr/sbin/parted /usr/bin/mktemp /usr/bin/date /usr/bin/basename /usr/sbin/resize2fs /usr/sbin/partprobe /usr/sbin/lvm /usr/sbin/blkid /usr/sbin/e2fsck /usr/sbin/xfs_growfs /usr/sbin/xfs_db
    # shellcheck disable=SC2154
    inst_hook pre-mount 99 "$moddir/increase-boot-partition.sh"
    inst_binary "$moddir/sfdisk.static" "/usr/sbin/sfdisk"
    inst_simple "$moddir/bigboot.sh" "/usr/bin/bigboot.sh"
}
