=====================================
LVM Snapshot Linux Role Release Notes
=====================================

.. contents:: Topics


v2.0.1
======

Minor Changes
-------------

- Add publish to Automation Hub to release workflow

Bugfixes
--------

- Fix release workflow prechecks

v2.0.0
======

Minor Changes
-------------

- bigboot - Rename internal variables with role name prefix
- initramfs - Rename internal variables with role name prefix
- shrink_lv - Rename internal variables with role name prefix

Breaking Changes / Porting Guide
--------------------------------

- Split lvm_snapshots role into snapshot_create, snapshot_revert and snapshot_remove

v1.1.2
======

Minor Changes
-------------

- Updated links in docs and workflows to reflect move to redhat-cop org

v1.1.1
======

Bugfixes
--------

- Fix "Failed to list block device properties" error
- Fix dracut path

v1.1.0
======

Major Changes
-------------

- New role, bigboot, to increase the boot partition while moving, and shrinking if needed, the adjacent partition
- New role, initramfs, to execute an atomic flow of building and using a temporary initramfs in a reboot and restoring the original one
- New role, shrink_lv, to decrease logical volume size along with the filesystem

v1.0.3
======

Minor Changes
-------------

- Changed the lvm_snapshots_boot_backup var default to false
- Removed unimplemented lvm_snapshots_use_boom var from the docs
- Revert - wait for snapshot to drain before returning

Bugfixes
--------

- Add task to ensure tar package is present
- Grub needs reinstall if /boot is on LVM
- Wrong kernel version booting after rolling back

v1.0.2
======

Minor Changes
-------------

- Create snapshots with normalized sizes

Bugfixes
--------

- Existing Snapshots with Different Name Cause verify_no_existing_snapshot.yml to Fail

v1.0.1
======

Major Changes
-------------

- Initial MVP release

Minor Changes
-------------

- Add boot backup support
- Add support for checking before resizing logical volumes

v1.0.0
======
