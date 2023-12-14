# create_snapshot role


The `create_snapshot` role is used to control the creation for a defined set of LVM snapshot volumes.
In addition, it can optionally save the Grub configuration and image files under /boot and configure settings to enable the LVM snapshot autoextend capability.
The role will verify free space and should fail if there is not enough or if any snapshots already exist for the given `create_snapshot_set_name`.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used to reduce the risk of more mundane system maintenance activities.

## Role Variables

### `create_snapshot_check_only`

When set to `true` the role will only verify there is enough free space for the specified snapshots and not create them.
Default `false`

### `create_snapshot_set_name`

The variable `create_snapshot_set_name` is used to identify the list of volumes to be operated upon.
The role will use the following naming convention when creating the snapshots:

`<Origin LV name>_<create_snapshot_set_name>`

### `create_snapshot_boot_backup`

Boolean to specify that the role should preserve the Grub configuration and image files under /boot required for booting the default kernel.
The files are preserved in a compressed tar archive at `/root/boot-backup-<create_snapshot_set_name>.tgz`. Default is `false`.

> **Warning**
>
> When automating RHEL in-place upgrades, do not perform a Grub to Grub2 migration as part of your upgrade playbook. It will invalidate your boot backup and cause a subsequent `revert` action to fail. For example, if you are using the [`upgrade`](https://github.com/redhat-cop/infra.leapp/tree/main/roles/upgrade#readme) role from the [`infra.leapp`](https://github.com/redhat-cop/infra.leapp) collection, do not set `update_grub_to_grub_2` to `true`. Grub to Grub2 migration should only be performed after the `remove` action has been performed to delete the snapshots and boot backup.

### `create_snapshot_snapshot_autoextend_threshold`

Configure the given `create_snapshot_autoextend_threshold` setting in lvm.conf before creating snapshots.

### `create_snapshot_snapshot_autoextend_percent`

Configure the given `create_snapshot_snapshot_autoextend_percent` setting in lvm.conf before creating snapshots.

### `create_snapshot_volumes`

This is the list of logical volumes for which snapshots are to be created and the size requirements for those snapshots. The volumes list is only required when the role is run with the check or create action.

### `vg`

The volume group of the origin logical volume for which a snapshot will be created.

### `lv`

The origin logical volume for which a snapshot will be created.

### `size`

The size of the logical volume according to the definition of the
[size](https://docs.ansible.com/ansible/latest/collections/community/general/lvol_module.html#parameter-size)
parameter of the `community.general.lvol` module.

To create thin provisioned snapshot of a thin provisioned volume, omit the `size` parameter or set it to `0`

## Example Playbooks

Perform space check and fail of there will not be enough space for all the snapshots in the set.
If there is sufficient space, proceed to create snapshots for the listed logical volumes.
Each snapshot will be sized to 20% of the origin volume size.
Snapshot autoextend settings are configured to enable free space in the volume group to be allocated to any snapshot that may exceed 70% usage in the future.
Files under /boot will be preserved.

```yaml
- hosts: all
  roles:
    - name: create_snapshot
      create_snapshot_set_name: ripu
      create_snapshot_snapshot_autoextend_threshold: 70
      create_snapshot_snapshot_autoextend_percent: 20
      create_snapshot_boot_backup: true
      create_snapshot_volumes:
        - vg: rootvg
          lv: root
          size: 2G
        - vg: rootvg
          lv: var
          size: 2G
```
