# shrink_lv

The `shrink_lv` role is used to decrease the size of logical volumes and the file system within them.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used for other purposes.

## Contents

The role contains the shell scripts to shrink the logical volume and file system, as well as the script wrapping it to run as part of the pre-mount step during the boot process.

## Role Variables

### `shrink_lv_devices`

The variable `shrink_lv_devices` is the list of logical volumes to shrink and the target size for those volumes.

#### `device`

The device that is mounted as listed under `/proc/mount`.
If the same device has multiple paths, e.g. `/dev/vg/lv` and `/dev/mapper/vg/lv` pass the path that is mounted

#### `size`

The target size of the logical volume and filesystem after the role has completed.
The value can be either in bytes or with optional single letter suffix (1024 bases).
See `Unit options` type `iec` of [`numfmt`](https://man7.org/linux/man-pages/man1/numfmt.1.html)

## Example of a playbook to run the role

The following yaml is an example of a playbook that runs the role against all hosts to shrink the logical volume `lv` in volume group `vg` to 4G.

```yaml
- name: Shrink Logical Volumes playbook
  hosts: all
  vars:
    shrink_lv_devices:
      - device: /dev/vg/lv
        size: 4G
  roles:
    - shrink_lv
```

# Validate execution
The script will add an entry to the kernel messages (`/dev/kmsg` or `/var/log/messages`) with success or failure.
In case of failure, it may also include an error message retrieved from the execution of the script.

A successful execution will look similar to this:
```bash
[root@localhost ~]# cat /var/log/messages |grep Resizing -A 2 -B 2
Oct 16 17:55:00 localhost /dev/mapper/rhel-root: 29715/2686976 files (0.2% non-contiguous), 534773/10743808 blocks
Oct 16 17:55:00 localhost dracut-pre-mount: resize2fs 1.42.9 (28-Dec-2013)
Oct 16 17:55:00 localhost journal: Resizing the filesystem on /dev/mapper/rhel-root to 9699328 (4k) blocks.#012The filesystem on /dev/mapper/rhel-root is now 9699328 blocks long.
Oct 16 17:55:00 localhost journal:  Size of logical volume rhel/root changed from 40.98 GiB (10492 extents) to 37.00 GiB (9472 extents).
Oct 16 17:55:00 localhost journal:  Logical volume rhel/root successfully resized.
```
