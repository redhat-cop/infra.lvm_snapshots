# initramfs

The `initramfs` role is included by the `shrink_lv` and `bigboot` roles to run an atomic flow of building and using a temporary initramfs in a reboot and restoring the original one.

The role is designed to be internal for this collection and support the automation of RHEL in-place upgrades, but can also be used for other purposes.

## Contents

To allow fast fail, the role provides a [`preflight.yml`](./tasks/preflight.yml) tasks file to that should be included early in the play that ultimately includes the [`main`](./tasks/main.yml) role that actually reboots the host. Refer the usage section below for example.

## Role Variables

All variables are optional

### `initramfs_add_modules`

`initramfs_add_modules` is a space-separated list of dracut modules to be added to the default set of modules.
See [`dracut --add`](https://man7.org/linux/man-pages/man8/dracut.8.html) option for details.

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


## Example role usage

We will refer to the `bigboot` role of this collection to explain how the `initramfs` role can be used. Let's look at the `tasks/main.yaml` of the `bigboot` role. After the required facts have been gathered, the [Validate initramfs preflight](https://github.com/redhat-cop/infra.lvm_snapshots/blob/2.1.0/roles/bigboot/tasks/main.yaml#L10-L13) task includes the `initramfs` role preflight tasks:

```yaml
- name: Validate initramfs preflight
  ansible.builtin.include_role:
    name: initramfs
    tasks_from: preflight
```

If this is successful, the `bigboot` role continues to perform additional tasks and checks specific to its function. With that done, it moves on to `tasks/do_bigboot_reboot.yml` which [configures a dracut pre-mount hook](https://github.com/redhat-cop/infra.lvm_snapshots/blob/2.1.0/roles/bigboot/tasks/do_bigboot_reboot.yml#L1-L15) to prepare for the customized initramfs reboot:

```yaml
- name: Copy dracut pre-mount hook files
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: /usr/lib/dracut/modules.d/99extend_boot/
    mode: "0554"
  loop:
    - bigboot.sh
    - module-setup.sh
    - sfdisk.static

- name: Resolve and copy pre-mount hook wrapper script
  ansible.builtin.template:
    src: increase-boot-partition.sh.j2
    dest: /usr/lib/dracut/modules.d/99extend_boot/increase-boot-partition.sh
    mode: '0554'
```

After that, it [includes](https://github.com/redhat-cop/infra.lvm_snapshots/blob/2.1.0/roles/bigboot/tasks/do_bigboot_reboot.yml#L17-L21) the main `initramfs` role which will create a custom initramfs built with the dracut hook configured above, reboot the host to run the hook, and lastly, restore the original initramfs after the reboot:

```yaml
- name: Create the initramfs and reboot to run the module
  vars:
    initramfs_add_modules: "extend_boot"
  ansible.builtin.include_role:
    name: initramfs
```

Also, note that while the `initramfs` role handles restoring the original initramfs, it is up to the including play to clean up the dracut hook files it configured. We see this with the [Remove dracut extend boot module](https://github.com/redhat-cop/infra.lvm_snapshots/blob/2.1.0/roles/bigboot/tasks/do_bigboot_reboot.yml#L23-L26) task that immediately follows the task including the `initramfs` role:

```yaml
- name: Remove dracut extend boot module
  ansible.builtin.file:
    path: /usr/lib/dracut/modules.d/99extend_boot
    state: absent
```

The `shrink_lv` role of this collection is another [example](https://github.com/redhat-cop/infra.lvm_snapshots/blob/2.1.0/roles/shrink_lv/tasks/main.yaml#L13-L37) of using the `initramfs` role that you may study.
