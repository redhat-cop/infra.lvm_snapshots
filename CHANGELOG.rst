=====================================
LVM Snapshot Linux Role Release Notes
=====================================

.. contents:: Topics


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
