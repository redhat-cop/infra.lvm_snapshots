=====================================
LVM Snapshot Linux Role Release Notes
=====================================

.. contents:: Topics

v2.1.0
======

Major Changes
-------------

- add bigboot support for Btrfs next partition

Minor Changes
-------------

- do bigboot LVM changes with Ansible instead of pre-mount hook
- new bigboot_partition_size variable to make bigboot role more idempotent
- show console log output from bigboot even if quiet kernel arg is set

v2.0.3
======

Bugfixes
--------

- Fix how locking is disabled for newer LVM versions
- Fix missing role metadata
- Fix potential space exhaustion when restoring previous initramfs

v2.0.2
======

Minor Changes
-------------

- Add bigboot progress messages so inpatient operators don't think their server is hung

Bugfixes
--------

- Clean up bad math in bigboot.sh
- Fix bigboot device not found error
- Fix bigboot fail when autoactivation property not set
- Fix vgs not found error
- Round down requested size to multiple of extent size
- Shorten bigboot.sh usage help message to not exceed the kmsg buffer
- Use sectors with sfdisk

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

