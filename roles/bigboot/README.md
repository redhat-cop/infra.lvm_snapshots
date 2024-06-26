# bigboot

The `bigboot` role is used to increase boot partition.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used for other purposes.

## Contents

The role contains the shell scripts to increase the size of the boot partition, as well as the script wrapping it to run as part of the pre-mount step during the boot process.
Finally, there is a copy of the [`sfdisk`](https://man7.org/linux/man-pages/man8/sfdisk.8.html) binary with version `2.38.1` to ensure the extend script will work regardless of the `util-linux` package installed in the target host.

> **WARNING!**
>
> All blocks of the partition above the boot partition are copied using `sfdisk` during the reboot and this can take serveral minutes or more depending on the size of that partition. The bigboot script periodically outputs progress messages to the system console to make it clear that the system is not in a "hung" state, but these progress messages may not be seen if `rhgb` or `quiet` kernel arguments are set. If the system is reset while the blocks are being copied, the partition will be irrcoverably corrupted. Do not assume the system is hung or force a reset during the bigboot reboot!

To learn more about how bigboot works, check out this [video](https://people.redhat.com/bmader/bigboot-demo.mp4).

## Role Variables

### `bigboot_partition_size` (String)

The variable `bigboot_partition_size` specifies the minimum required size of the boot partition. If the boot partition is already equal to or greater than the given size, the role will end gracefully making no changes. The value can be either in bytes or with optional single letter suffix (1024 bases) using [human_to_bytes](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/human_to_bytes_filter.html) filter plugin.

### `bigboot_size` (String)

This variable is deprecated and will be removed in a future release. Use `bigboot_partition_size` instead.

The variable `bigboot_size` specifies by how much the size of the boot partition is to be increased. The value can be either in bytes or with optional single letter suffix (1024 bases) using [human_to_bytes](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/human_to_bytes_filter.html) filter plugin. 

> **Note**
>
> The size increase may be slightly less than the specified value as the role will round down to the nearest multiple of the extent size of the LVM physical volume in the partition above the boot partition.

## Example of a playbook to run the role
The following yaml is an example of a playbook that runs the role against a group of hosts named `rhel` and increasing the size of its boot partition by 1G.
The boot partition is automatically retrieved by the role by identifying the existing mounted partition to `/boot` and passing the information to the script using the `kernel_opts`.

```yaml
- name: Extend boot partition playbook
  hosts: all
  vars:
    bigboot_partition_size: 1G
  roles:
    - bigboot
```

# Validate execution
The script will add an entry to the kernel messages (`/dev/kmsg`) with success or failure and the time it took to process.
In case of failure, it may also include an error message retrieved from the execution of the script.

A successful execution will look similar to this:
```bash
[root@localhost ~]# dmesg |grep pre-mount
[  357.163522] [dracut-pre-mount] Boot partition /dev/vda1 successfully increased by 1G (356 seconds)
```
