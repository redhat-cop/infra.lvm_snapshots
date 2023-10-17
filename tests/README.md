# Testing the LVM Snapshot Role

## Prerequisites

- All the tests are in the form of ansible playbooks.
- All playbooks expect that the target machine will have a secondary storage device to be used for testing.

## Variables
The variables may be passed as part of the inventory or using a separate file.

```yaml
device: < device node without `/dev`. e.g. vdb >
```

## Ansible Configuration

In order to run the tests from the repo without having to install them,
the tests directory includes an [ansible.cfg](./ansible.cfg) file.
Make sure to point to it when running the test playbook

## Running a test

### Inventory file

In this example, the `device` parameter is passed in the `inventory.yml` file
```yaml
all:
  hosts:
    <FQDN of test machine>:
      device: vdb
```

### Command line

Running the [snapshot revert playbook](./test-revert-playbook.yml) test from the repo

```bash
ANSIBLE_CONFIG=./tests/ansible.cfg ansible-playbook -K  -i inventory.yml tests/test-revert-playbook.yml
```
