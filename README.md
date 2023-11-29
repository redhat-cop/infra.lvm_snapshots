# LVM Snapshots Collection

[![Ansible Lint](https://github.com/swapdisk/lvm_snapshots/workflows/Ansible%20Lint/badge.svg?event=push)](https://github.com/swapdisk/lvm_snapshots/actions) [![PyLint](https://github.com/swapdisk/lvm_snapshots/workflows/PyLint/badge.svg?event=push)](https://github.com/swapdisk/lvm_snapshots/actions)

## Overview

A reliable snapshot/rollback capability is a key feature required to enable the success of RHEL In-place Upgrade automation solutions. Without it, users will be wary of using the solution because of the potential risk that their applications may not function properly after the OS upgrade. Including automation so that snapshot creation happens right before the OS upgrade reduces this risk. If there are any application issues uncovered after the OS upgrade, a rollback playbook can be executed to instantly revert the environment back to the original state as it was before the upgrade. Application teams will no longer have an excuse not to use in-place upgrades to bring their RHEL estate into compliance.

## Roles

These are the roles included in the collection. Follow the links below to see the detailed documentation and example playbooks for each role.

- [`lvm_snapshots`](./roles/lvm_snapshots/) - controls creation and rollback for a defined set of LVM snapshot volumes
- [`bigboot`](./roles/bigboot/) - controls increasing of the boot partition while moving, and shrinking if needed, the adjacent partition
- [`initramfs`](./roles/initramfs/) - controls the atomic flow of building and using a temporary initramfs in a reboot and restoring the original one
- [`shrink_lv`](./roles/shrink_lv/) - controls decreasing logical volume size along with the filesystem

Additional roles are planned to support shrinking logical volumes to make free space available in a volume group and relocating physical volumes to enable increasing the size of a /boot /partition.

## Installing the collection from Ansible Galaxy

Before using this collection, you need to install it with the Ansible Galaxy command-line tool:

```bash
ansible-galaxy collection install infra.lvm_snapshots
```

You can also include it in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`, using the format:

```yaml
---
collections:
  - name: infra.lvm_snapshots
```

Note that if you install the collection from Ansible Galaxy, it will not be upgraded automatically when you upgrade the `ansible` package. To upgrade the collection to the latest available version, run the following command:

```bash
ansible-galaxy collection install infra.lvm_snapshots --upgrade
```

You can also install a specific version of the collection, for example, if you need to downgrade when something is broken in the latest version (please report an issue in this repository). Use the following syntax to install version `1.0.0`:

```bash
ansible-galaxy collection install infra.lvm_snapshots:==1.0.0
```

See [Using Ansible collections](https://docs.ansible.com/ansible/devel/user_guide/collections_using.html) for more details.

## Contributing

We appreciate participation from any new contributors. Get started by opening an issue or pull request. Refer to our [contribution guide](CONTRIBUTING.md) for more information.

## Reporting issues

Please open a [new issue](https://github.com/swapdisk/lvm_snapshots/issues/new/choose) for any bugs or security vulnerabilities you may encounter. We also invite you to open an issue if you have ideas on how we can improve the solution or want to make a suggestion for enhancement.

## More information

This collection is just one building block of our larger initiative to make RHEL in-place upgrade automation that works at enterprise scale. Learn more about our end-to-end approach for automating RHEL in-place upgrades at this [blog post](https://red.ht/bobblog).

## Release notes

See the [changelog](https://github.com/swapdisk/lvm_snapshots/tree/main/CHANGELOG.rst).

## Licensing

MIT

See [LICENSE](LICENSE) to see the full text.
