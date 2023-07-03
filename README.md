# Snapshot Linux Role

__High-level design and requirements to support use case with the RHEL In-place Upgrade automation__

## Overview

A reliable snapshot/rollback capability is a key feature required to enable the success of RHEL In-place Upgrade automation solutions. Without it, users will be wary of using the solution because of the potential risk that their applications may not function properly after the OS upgrade. Including automation so that snapshot creation happens right before the OS upgrade reduces this risk. If there are any application issues uncovered after the OS upgrade, a rollback playbook can be executed to instantly revert the environment back to the original state as it was before the upgrade. Application teams will no longer have an excuse not to use in-place upgrades to bring their RHEL estate into compliance.

## Proposed Design

The proposed design will implement a new `snapshot` Linux Role. The role will accept variables used to control creation/rollback and specify the size of a set of LVM snapshot volumes.

### Role Variables

#### `lvm_snapshots_set_name`

The variable `lvm_snapshots_set_name` is used to identify the list of volumes to be operated upon. The role will use the following naming convention when creating the snapshots:

`<Origin LV name>_<lvm_snapshots_set_name>`

When the role is run with a revert or remove action, this naming convention will be used to identify the snapshots to be merged or removed.

#### `lvm_snapshots_action`

The role will accept an action variable that will control the operation to be performed:

- `check` - verify there is enough free space for the specified snapshots
- `create` - verify free space as above and create snapshots
- `revert` - merge snapshots to origin and reboot (i.e., rollback)
- `remove` - remove snapshots

Both the `check` and `create` actions will verify free space and should fail if there is not enough. A `check` or `create` action should fail if any snapshots already exist for the given `snapshot_set_name`.

The `revert` action will verify that all snapshots in the set are still active state before doing any merges. This is to prevent rolling back if any snapshots have become invalidated in which case the `revert` action should fail.

#### `lvm_snapshots_boot_backup`

Boolean to specify that the `create` action should preserve image files under /boot required for booting the default kernel. The preserved image files should be restored with a `revert` action and they should be unlinked with a `remove` action. The images files are preserved using hard links so as to not consume any additional space under /boot. Default is true.

#### `lvm_snapshots_use_boom`

Boolean to specify that a boom profile should be created to add a Grub boot entry for the snapshot set. Default is true.

#### `lvm_snapshots_snapshot_autoextend_threshold`

Configure the given `snapshot_autoextend_threshold` setting in lvm.conf before creating snapshots.

#### `lvm_snapshots_snapshot_autoextend_percent`

Configure the given `snapshot_autoextend_percent` setting in lvm.conf before creating snapshots.

#### `lvm_snapshots_volumes`

This is the list of logical volumes for which snapshots are to be created and the size requirements for those snapshots. The volumes list is only required when the role is run with the check or create action.

#### `vg`

The volume group of the origin logical volume for which a snapshot should be created.

#### `lv`

The origin logical volume for which a snapshot should be created.

#### `size`

The size of the logical volume according to the definition of the
[size](https://docs.ansible.com/ansible/latest/collections/community/general/lvol_module.html#parameter-size)
parameter of the `community.general.lvol` module.

To create thin provisioned snapshot of a thin provisioned volume, omit the `size` parameter or set it to `0`

### Example Playbooks

#### Create snapshots

Perform space check and fail of there will not be enough space for all the snapshots in the set. If there is sufficient space, proceed to create snapshots for the listed logical volumes. Each snapshot will be sized to 20% of the origin volume or 4 GiB, whichever is greater. Snapshot autoextend settings are configured to enable free space in the volume group to be allocated to any snapshot that may exceed 70% usage in the future. A boom profile will be created for the snapshot and required images files under /boot will be preserved.

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: create
      lvm_snapshots_snapshot_autoextend_threshold: 70
      lvm_snapshots_snapshot_autoextend_percent: 20
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
      lvm_snapshots_volumes:
        - vg: rootvg
          lv: root
          extents: 20%ORIGIN
        - vg: rootvg
          lv: var
          extents: 20%ORIGIN
```

#### Rollback

This playbook rolls back the host using the snapshots created above. After verifying that all snapshots are still valid, each logical volume in the snapshot set is merged. The image files under /boot will be restored and the boom profile will be deleted. Then the host will be rebooted.

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: revert
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
```

#### Commit

A commit playbook is used when users are comfortable the snapshots are not needed any longer. Each snapshot in the snapshot set is removed, the preserved image files under /boot are unlinked and the boom profile is deleted.

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      lvm_snapshots_set_name: ripu
      lvm_snapshots_action: remove
      lvm_snapshots_boot_backup: true
      lvm_snapshots_use_boom: true
```
