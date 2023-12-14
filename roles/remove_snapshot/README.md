# remove_snapshot role

The `remove_snapshot` role is used to remove snapshots.
In addition, it removes the Grub configuration and image files under /boot if it was previously backed up
It is intended to be used along with the `create_snapshot` role.

The role is designed to support the automation of RHEL in-place upgrades, but can also be used to reduce the risk of more mundane system maintenance activities.

## Role Variables

### `remove_snapshot_set_name`

The variable `remove_snapshot_set_name` is used to identify the list of volumes to be operated upon.
The role will use the following naming convention when reverting the snapshots:

`<Origin LV name>_<remove_snapshot_set_name>`

This naming convention will be used to identify the snapshots to be removed.

## Example Playbooks

### Commit

A commit playbook is used when users are comfortable the snapshots are not needed any longer.
Each snapshot in the snapshot set is removed and the backed up image files from /boot are deleted.

```yaml
- hosts: all
  roles:
    - name: remove_snapshot
      remove_snapshot_set_name: ripu
```
