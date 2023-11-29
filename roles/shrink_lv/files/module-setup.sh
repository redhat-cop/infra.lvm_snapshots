#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

check(){
    return 0
}

install() {
    inst_multiple -o /usr/bin/numfmt /usr/bin/findmnt /usr/bin/lsblk /usr/sbin/lvm /usr/bin/awk /usr/bin/sed /usr/bin/mktemp /usr/bin/date /usr/bin/head /usr/sbin/blockdev /usr/sbin/tune2fs /usr/sbin/resize2fs /usr/bin/cut /usr/sbin/fsadm /usr/sbin/fsck.ext4
    inst_hook pre-mount 99 "$moddir/shrink-start.sh"
    inst_simple "$moddir/shrink.sh" "/usr/bin/shrink.sh"
}
