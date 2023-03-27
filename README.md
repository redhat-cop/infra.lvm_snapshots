# Snapshot Linux Role

__High-level design and requirements to support use case with the RHEL In-place Upgrade automation__

## Overview

A reliable snapshot/rollback capability is a key feature required to enable the success of RHEL In-place Upgrade automation solutions. Without it, users will be wary of using the solution because of the potential risk that their applications may not function properly after the OS upgrade. Including automation so that snapshot creation happens right before the OS upgrade reduces this risk. If there are any application issues uncovered after the OS upgrade, a rollback playbook can be executed to instantly revert the environment back to the original state as it was before the upgrade. Application teams will no longer have an excuse not to use in-place upgrades to bring their RHEL estate into compliance. 

## Proposed Design

The proposed design will implement a new `snapshot` Linux Role. The role will accept variables used to control creation/rollback and specify the size of a set of LVM snapshot volumes.

### Role Variables

#### `snapshot_set_name`

The variable `snapshot_set_name` is used to identify the list of volumes to be operated upon. When the snapshots created, the role will use the following naming convention:

`<Origin LV name>_<snapshot_set_name>`

When the role is run with a revert or remove action, this naming convention will be used to identify the snapshots to be merged or removed. 

This variable is not required when the role is run with the check action. 

#### `action`

The role will accept an action variable that will control the operation to be performed: 

- `check` - verify there is enough free space for the specified snapshots
- `create` - verify free space as above and create snapshots
- `revert` - merge snapshots to origin and reboot (i.e., rollback)
- `remove` - remove snapshots

Both the `check` and `create` actions will verify free space and should fail if there is not enough. The `create` action should fail if any snapshots already exist for the given `snapshot_set_name`.

#### `use_boom`

Boolean to specify that boom should be used to add a boot entry for snapshots and make a backup of /boot for rolling back. Default is true. 

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

### Example Playbook

```yaml
- hosts: all
  roles:
    - name: linux-system-roles.snapshot
      snapshot_set_name: ripu
      action: create
      use_boom: true
      snapshot_autoextend_threshold: 70
      snapshot_autoextend_percent: 20
      volumes:
        - path: rootvg/root
          extents: 20%ORIGIN    
          size: 4G
        - path: rootvg/var
          extents: 20%ORIGIN    
          size: 4G
```

