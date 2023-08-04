# lvm_snapshots role


The `lvm_snapshots` role is used to control the creation and rollback for a defined set of LVM snapshot volumes. In addition, it can optionally save the Grub configuration and image files under /boot, create a snapshot boom entry, and configure settings to enable the LVM snapshot autoextend capability.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used to reduce the risk of more mundane system maintenance activities.

## Role Variables

### `lvm_snapshots_set_name`

The variable `lvm_snapshots_set_name` is used to identify the list of volumes to be operated upon. The role will use the following naming convention when creating the snapshots:

`<Origin LV name>_<lvm_snapshots_set_name>`

When the role is run with a revert or remove action, this naming convention will be used to identify the snapshots to be merged or removed.

### `lvm_snapshots_action`

The role will accept an action variable that will control the operation to be performed:

- `check` - verify there is enough free space for the specified snapshots
- `create` - verify free space as above and create snapshots
- `revert` - merge snapshots to origin and reboot (i.e., rollback)
- `remove` - remove snapshots

Both the `check` and `create` actions will verify free space and should fail if there is not enough. A `check` or `create` action should fail if any snapshots already exist for the given `snapshot_set_name`.

The `revert` action will verify that all snapshots in the set are still active state before doing any merges. This is to prevent rolling back if any snapshots have become invalidated in which case the `revert` action should fail.

### `lvm_snapshots_boot_backup`

Boolean to specify that the `create` action should preserve the Grub configuration and image files under /boot required for booting the default kernel. The preserved files will be restored with a `revert` action and they will be deleted with a `remove` action. The files are preserved in a compressed tar archive at `/root/boot-backup-<lvm_snapshots_set_name>.tgz`. Default is true.

> **Warning**
>
> When automating RHEL in-place upgrades, do not perform a Grub to Grub2 migration as part of your upgrade playbook. It will invalidate your boot backup and cause a subsequent `revert` action to fail. For example, if you are using the [`upgrade`](https://github.com/redhat-cop/infra.leapp/tree/main/roles/upgrade#readme) role from the [`infra.leapp`](https://github.com/redhat-cop/infra.leapp) collection, do not set `update_grub_to_grub_2` to `true`. Grub to Grub2 migration should only be performed after the `remove` action has been performed to delete the snapshots and boot backup.

### `lvm_snapshots_use_boom`

Boolean to specify that a boom profile will be created to add a Grub boot entry for the snapshot set. Default is true.

### `lvm_snapshots_snapshot_autoextend_threshold`

Configure the given `snapshot_autoextend_threshold` setting in lvm.conf before creating snapshots.

### `lvm_snapshots_snapshot_autoextend_percent`

Configure the given `snapshot_autoextend_percent` setting in lvm.conf before creating snapshots.

### `lvm_snapshots_volumes`

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

### Create snapshots

Perform space check and fail of there will not be enough space for all the snapshots in the set. If there is sufficient space, proceed to create snapshots for the listed logical volumes. Each snapshot will be sized to 20% of the origin volume size. Snapshot autoextend settings are configured to enable free space in the volume group to be allocated to any snapshot that may exceed 70% usage in the future. A boom profile will be created for the snapshot and required images files under /boot will be preserved.

```yaml
- hosts: all
  roles:
    - name: lvm_snapshots
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: create
      lvm_snapshots_snapshot_autoextend_threshold: 70
      lvm_snapshots_snapshot_autoextend_percent: 20
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
      lvm_snapshots_volumes:
        - vg: rootvg
          lv: root
          size: 20%ORIGIN
        - vg: rootvg
          lv: var
          size: 20%ORIGIN
```

### Rollback

This playbook rolls back the host using the snapshots created above. After verifying that all snapshots are still valid, each logical volume in the snapshot set is merged. The image files under /boot will be restored and the boom profile will be deleted. Then the host will be rebooted.

```yaml
- hosts: all
  roles:
    - name: lvm_snapshots
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: revert
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
```

### Commit

A commit playbook is used when users are comfortable the snapshots are not needed any longer. Each snapshot in the snapshot set is removed, the preserved image files under /boot are unlinked and the boom profile is deleted.

```yaml
- hosts: all
  roles:
    - name: lvm_snapshots
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: remove
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
```
