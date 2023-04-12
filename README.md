# Snapshot Linux Role

__High-level design and requirements to support use case with the RHEL In-place Upgrade automation__

## Overview

A reliable snapshot/rollback capability is a key feature required to enable the success of RHEL In-place Upgrade automation solutions. Without it, users will be wary of using the solution because of the potential risk that their applications may not function properly after the OS upgrade. Including automation so that snapshot creation happens right before the OS upgrade reduces this risk. If there are any application issues uncovered after the OS upgrade, a rollback playbook can be executed to instantly revert the environment back to the original state as it was before the upgrade. Application teams will no longer have an excuse not to use in-place upgrades to bring their RHEL estate into compliance.

## Proposed Design

The proposed design will implement a new `snapshot` Linux Role. The role will accept variables used to control creation/rollback and specify the size of a set of LVM snapshot volumes.

### Role Variables

#### `snapshot_set_name`

The variable `snapshot_set_name` is used to identify the list of volumes to be operated upon. The role will use the following naming convention when creating the snapshots:

`<Origin LV name>_<snapshot_set_name>`

When the role is run with a revert or remove action, this naming convention will be used to identify the snapshots to be merged or removed.

#### `action`

The role will accept an action variable that will control the operation to be performed:

- `check` - verify there is enough free space for the specified snapshots
- `create` - verify free space as above and create snapshots
- `revert` - merge snapshots to origin and reboot (i.e., rollback)
- `remove` - remove snapshots

Both the `check` and `create` actions will verify free space and should fail if there is not enough. A `check` or `create` action should fail if any snapshots already exist for the given `snapshot_set_name`.

The `revert` action will verify that all snapshots in the set are still active state before doing any merges. This is to prevent rolling back if any snapshots have become invalidated in which case the `revert` action should fail.

#### `use_boom`

Boolean to specify that a boom profile should be created to add a boot entry for the snapshot set and a backup of /boot should be made for rolling back. Default is true.

#### `snapshot_autoextend_threshold`

Configure the given `snapshot_autoextend_threshold` setting in lvm.conf before creating snapshots.

#### `snapshot_autoextend_percent`

Configure the given `snapshot_autoextend_percent` setting in lvm.conf before creating snapshots.

#### `volumes`

This is the list of logical volumes for which snapshots are to be created and the size requirements for those snapshots. The volumes list is only required when the role is run with the check or create action.

##### `path`

The path in <VG name>/<LV name> format is the origin logical volume for which a snapshot should be created.

##### `extents`

Specifies the snapshot size as a number of physical extents or any allowed percentage syntax of `lvcreate --extents` command option, for example, `50%ORIGIN`.

__NOTE:__ Each volume listed must have at least one of `extent`, `size`, or `thin: true` variable set. If both `extent` and `size` are given, the setting that results in a larger snapshot size prevails.

##### `size`

Specifies the absolute snapshot size. The size is in MiB unless an optional unit suffix is given, for example, `4G` would be 4 GiB.

##### `thin`

Boolean to specify that thin provisioning should be used to create the snapshot. This is only valid if the origin volume is thin provisioned.

### Example Playbooks

#### Create snapshots

Perform space check and fail of there will not be enough space for all the snapshots in the set. If there is sufficient space, proceed to create snapshots for the listed logical volumes. Each snapshot will be sized to 20% of the origin volume or 4 GiB, whichever is greater. Snapshot autoextend settings are configured to enable free space in the volume group to be allocated to any snapshot that may exceed 70% usage in the future. A boom profile will be created for the snapshot and /boot will be backed up.

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      snapshot_set_name: ripu
      action: create
      snapshot_autoextend_threshold: 70
      snapshot_autoextend_percent: 20
      use_boom: true
      volumes:
        - path: rootvg/root
          extents: 20%ORIGIN
          size: 4G
        - path: rootvg/var
          extents: 20%ORIGIN
          size: 4G
```

#### Rollback

Rollback the host using the snapshots created above. The playbook will merge each snapshot in the snapshot set. The snapshot set boom profile will be deleted and /boot partition restored. Then the host will be rebooted.

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      snapshot_set_name: ripu
      action: revert
      use_boom: true
```
