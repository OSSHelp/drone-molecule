# drone-molecule

[![Build Status](https://drone.osshelp.ru/api/badges/drone/drone-molecule/status.svg?ref=refs/heads/master)](https://drone.osshelp.ru/drone/drone-molecule)

## Description

Docker image for testing and release Ansible roles via Molecule (+testinfra).

## Usage

### Modes (action)

- `test` - tests only
- `upload` - upload only
- `release` - tests and upload

### Other settings

- `scenario` - molecule scenario. default: `default`
- `lxd_remote_host` and `lxd_remote_port` - LXD connection parameters
- `release_directory` - the name of the local temporary folder to create an archive with the role
- `ansible_requirements` - The path to the requirements file that will be used to load roles. (requirements.yml by default)
- `ansible_profiler` - an option to control ansible-profiler (true by default)
- `ansible_errors_fatal` - whether to consider all errors during the execution of roles at the stage of rolling the playbook fatal (true by default).
- `minio_alias` - the name that will be used when generating the variable for minio-client. ("remote" by default)
- `minio_host` and `minio_bucket` - minio connection parameters
- `upload_prefix` - nested directories inside bucket
- `upload_as` - override archive name with role
- `minio_debug` - debug mode for minio
- `release_alias` - upload alias. Default: tag -> stable, master branch -> latest, any branch -> branch name
- `debug` - debug mode

### Common example

``` yaml
---
kind: pipeline
name: test

steps:
  - name: test
    image: osshelp/drone-molecule
    environment:
      LXD_REMOTE_PASSWORD:
        from_secret: lxd_remote_password
    settings:
      action: test

---
kind: pipeline
name: publish

depends_on: [test]
trigger:
  status: [success]
  event: [push, tag]
  ref:
    - refs/heads/*
    - refs/tags/*

steps:
  - name: publish
    image: osshelp/drone-molecule
    environment:
      MINIO_USER:
        from_secret: minio_user
      MINIO_SECRET:
        from_secret: minio_secret
    settings:
      action: upload
```

### Internal usage

For internal purposes and OSSHelp customers we have an alternative image url:

``` yaml
  image: oss.help/drone/molecule
```

There is no difference between the DockerHub image and the oss.help/drone image.

## Links

- [Our article](https://oss.help/kb3882)

## TODO

- add docker client (?)
