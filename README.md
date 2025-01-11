# EISEI (衛星)

Collection of Red Hat Satellite related scripts, Ansible playbooks etc for monthly task etc.

## WARNING

The latest version has not been tested at all yet.

## Description

These playbooks, scripts, templates are used by myself to learn bash, ansible, satellite.

## Usage

### satellite_align_contenthostconfig.yml

This playbook is to gather and collect the current configuration of content host
in the environment.

Please specify RedHat VM only host groups, otherwise would fail because the playbook
checks and only run on RHEL VMs.

#### Requirement:

[Extra vars]
email:
  host: "your SMTP server"
  port: "your SMTP server required port #"
  toAddr: "To email address, can be a list"
  ccAddr: "Cc email address, can be a list"
  fromAddr: "The mail address to send the email"
  replyAddr: "Who the recipient will reply to"

#### TODO:

1. Move email task to its own role/task.
3. Ansible-fy other shelly tasks.

### satellite_align_contenthostconfig.yml

This playbook is to update content host's rhsm.conf so that it would connect to the
correct capsule loadbalancer.

Please specify RedHat VM only host groups, and depends on host variable `location`.
It will fail if it's not RHEL and host variables doesn't have location assigned.
This location is assigned by Azure dynamic host inventory playbook.

#### Requirement:

[Host variables]
location: "Azure VM region"

[Extra vars]
email:
  host: "your SMTP server"
  port: "your SMTP server required port #"
  toAddr: "To email address, can be a list"
  ccAddr: "Cc email address, can be a list"
  fromAddr: "The mail address to send the email"
  replyAddr: "Who the recipient will reply to"

