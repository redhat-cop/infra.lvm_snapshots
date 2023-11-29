# initramfs

The `initramfs` role is used to run an atomic flow of building and using a temporary initramfs in a reboot and restoring the original one.

The role is designed to be internal for this collection and support the automation of RHEL in-place upgrades, but can also be used for other purposes.

## Contents

To allow fast fail, the role provides a [`preflight.yml`](./tasks/preflight.yml) tasks file to be used at the start of the playbook.
Please note that the [`main`](./tasks/main.yml) task file will not run the preflight checks

## Role Variables

All variables are optional

### `initramfs_add_modules`

`initramfs_add_modules` is a a space-separated list of dracut modules to be added to the default set of modules.
See [`dracut`](https://man7.org/linux/man-pages/man8/dracut.8.html) `-a` parameter for details.

### `initramfs_backup_extension`

`initramfs_backup_extension` is the file extension for the backup initramfs file.

Defaults to `old`

### `initramfs_post_reboot_delay`

`initramfs_post_reboot_delay` sets the amount of Seconds to wait after the reboot command was successful before attempting to validate the system rebooted successfully.
The value is used for [`post_reboot_delay`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/reboot_module.html#parameter-post_reboot_delay) parameter

Defaults to `30`

### `initramfs_reboot_timeout`

`initramfs_reboot_timeout` sets the maximum seconds to wait for machine to reboot and respond to a test command.
The value is used for [`reboot_timeout`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/reboot_module.html#parameter-reboot_timeout) parameter

Defaults to `7200`


## Example of a playbook to run the role
The following yaml is an example of a playbook that runs the role against a group of hosts named `rhel` and increasing the size of its boot partition by 1G.
The boot partition is automatically retrieved by the role by identifying the existing mounted partition to `/boot` and passing the information to the script using the `kernel_opts`.

```yaml
- name: Extend boot partition playbook
  hosts: all
  tasks:
  - name: Validate initramfs preflight
    ansible.builtin.include_role:
      name: initramfs
      tasks_from: preflight
  - name: Create the initramfs and reboot to run the module
    vars:
      initramfs_add_modules: "my_extra_module"
    ansible.builtin.include_role:
      name: initramfs
```
