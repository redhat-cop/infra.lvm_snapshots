# snapshot_revert role


The `snapshot_revert` role is used to merge snapshots to origin and reboot (i.e., rollback).
The role will verify that all snapshots in the set are still in active state before doing any merges.
This is to prevent rolling back if any snapshots have become invalidated in which case the role should fail.
In addition, it restores the Grub configuration and image files under /boot is it was previously backed up
It is intended to be used along with the `snapshot_create` role.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used to reduce the risk of more mundane system maintenance activities.

## Role Variables

### `snapshot_revert_set_name`

The variable `snapshot_revert_set_name` is used to identify the list of volumes to be operated upon.
The role will use the following naming convention when reverting the snapshots:

`<Origin LV name>_<snapshot_revert_set_name>`

This naming convention will be used to identify the snapshots to be merged.

The `revert` action will verify that all snapshots in the set are still active state before doing any merges. This is to prevent rolling back if any snapshots have become invalidated in which case the `revert` action should fail.

## Example Playbooks

This playbook rolls back the host using the snapshots created using the `snapshot_create` role.
After verifying that all snapshots are still valid, each logical volume in the snapshot set is merged.
The image files under /boot will be restored and then the host will be rebooted.

```yaml
- hosts: all
  roles:
    - name: snapshot_revert
      snapshot_revert_set_name: ripu
```
