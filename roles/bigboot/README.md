# bigboot

The `bigboot` role is used to increase boot partition.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used for other purposes.

## Contents

The role configures a dracut pre-mount hook that executes during a reboot to increase the size of the boot partition and filesystem. To make room for the boot size increase, the role first shrinks the size of the next partition after the boot partition. This next partition must contain either an LVM physical volume or a Btrfs filesystem volume. There must be sufficient free space in the LVM volume group or Btrfs filesystem to accommodate the reduced size.

> **WARNING!**
>
> All blocks of the partition above the boot partition are copied using `sfdisk` during the reboot and this can take several minutes or more depending on the size of that partition. The bigboot script periodically outputs progress messages to the system console to make it clear that the system is not in a "hung" state, but these progress messages may not be seen if `rhgb` or `quiet` kernel arguments are set. If the system is reset while the blocks are being copied, the partition will be irrcoverably corrupted. Do not assume the system is hung or force a reset during the bigboot reboot!

To learn more about how bigboot works, check out this [video](https://people.redhat.com/bmader/bigboot-demo.mp4).

## Role Variables

### `bigboot_partition_size` (String)

The variable `bigboot_partition_size` specifies the minimum required size of the boot partition. If the boot partition is already equal to or greater than the given size, the role will end gracefully making no changes. The value can be either in bytes or with optional single letter suffix (1024 bases) using [human_to_bytes](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/human_to_bytes_filter.html) filter plugin.

### `bigboot_size` (String)

This variable is deprecated and will be removed in a future release. Use `bigboot_partition_size` instead.

The variable `bigboot_size` specifies by how much the size of the boot partition is to be increased. The value can be either in bytes or with optional single letter suffix (1024 bases) using [human_to_bytes](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/human_to_bytes_filter.html) filter plugin.

> **Note**
>
> The size increase may be slightly less than the specified value as the role will round down to the nearest multiple of the LVM volume group extent size or Btrfs sector size used for the next partition after the boot partition.

## Example playbook
The following yaml demonstrates an example playbook that runs the role to increase the size of the target hosts boot partition to 1.5G:

```yaml
- name: Extend boot partition playbook
  hosts: all
  vars:
    bigboot_partition_size: 1.5G
  roles:
    - bigboot
```

# Validate execution
The "Validate boot filesystem new size" task at the end of the run will indicate success or failure of the boot partition size increase. For example:

```
TASK [bigboot : Validate boot filesystem new size] ****************************************
ok: [fedora] => {
    "changed": false,
    "msg": "Boot filesystem size is now 1.44 GB (503.46 MB increase)"
```

If the boot partition was already equal to or greater than the given size, the bigboot pre-mount hook configuration is skipped and the host will not reboot. In this case, the run will end with the "Validate increase requested" task indicating nothing happened. For example:

```
TASK [bigboot : Validate increase requested] **********************************************
ok: [fedora] => {
    "msg": "Nothing to do! Boot partition already equal to or greater than requested size."
}
```

During the reboot, the bigboot pre-mount hook logs progress messages to the console. After the reboot, `journalctl` can be used to review the log output. For example, a successful run will look similar to this:
```bash
# journalctl --boot --unit=dracut-pre-mount
Jul 02 09:40:12 fedora systemd[1]: Starting dracut-pre-mount.service - dracut pre-mount hook...
Jul 02 09:40:12 fedora dracut-pre-mount[498]: bigboot: Shrinking partition vda3 by 536870912
Jul 02 09:40:12 fedora dracut-pre-mount[498]: bigboot: Moving up partition vda3 by 536870912
Jul 02 09:40:16 fedora dracut-pre-mount[508]: bigboot: Partition move is progressing, please wait! (00:00:01)
Jul 02 09:40:48 fedora dracut-pre-mount[498]: bigboot: Increasing boot partition vda2 by 536870912
Jul 02 09:40:49 fedora dracut-pre-mount[498]: bigboot: Updating kernel partition table
Jul 02 09:40:50 fedora dracut-pre-mount[498]: bigboot: Growing the /boot ext4 filesystem
Jul 02 09:40:50 fedora dracut-pre-mount[528]: e2fsck 1.47.0 (5-Feb-2023)
Jul 02 09:40:50 fedora dracut-pre-mount[528]: Pass 1: Checking inodes, blocks, and sizes
Jul 02 09:40:50 fedora dracut-pre-mount[528]: Pass 2: Checking directory structure
Jul 02 09:40:50 fedora dracut-pre-mount[528]: Pass 3: Checking directory connectivity
Jul 02 09:40:50 fedora dracut-pre-mount[528]: Pass 4: Checking reference counts
Jul 02 09:40:50 fedora dracut-pre-mount[528]: Pass 5: Checking group summary information
Jul 02 09:40:50 fedora dracut-pre-mount[528]: /dev/vda2: 38/65536 files (10.5% non-contiguous), 83665/262144 blocks
Jul 02 09:40:50 fedora dracut-pre-mount[529]: resize2fs 1.47.0 (5-Feb-2023)
Jul 02 09:40:50 fedora dracut-pre-mount[529]: Resizing the filesystem on /dev/vda2 to 393216 (4k) blocks.
Jul 02 09:40:50 fedora dracut-pre-mount[529]: The filesystem on /dev/vda2 is now 393216 (4k) blocks long.
Jul 02 09:40:50 fedora dracut-pre-mount[493]: Boot partition vda2 successfully increased by 536870912 (38 seconds)
```
