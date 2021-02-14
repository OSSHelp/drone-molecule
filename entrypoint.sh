#!/bin/bash

[ "${PLUGIN_DEBUG}" = "true" ] && { set -x; env; }

function show_notice()  { echo -e "\e[34m[NOTICE. $(date '+%Y/%m/%d-%H:%M:%S')]\e[39m ${1}"; }
function show_warning() { echo -e "\e[33m[WARNING. $(date '+%Y/%m/%d-%H:%M:%S')]\e[39m ${1}" >&2; }
function show_error()   { echo -e "\e[31m[ERROR. $(date '+%Y/%m/%d-%H:%M:%S')]\e[39m ${1}" >&2; exit 1; }

function generate_release_alias() {
  test -n "${DRONE_BRANCH}" && {
    test "${DRONE_BRANCH}" == "master" && release_alias="latest" \
    || release_alias="${DRONE_BRANCH}"
  }
  test -n "${DRONE_TAG}" && release_alias="stable"
}

function check_and_set_vars() {
  show_notice "Preparing variables for the build"

  # generic default
  required_action="test"
  required_scenario="default"
  # for testing
  lxd_remote_name="build"
  lxd_remote_host="172.17.0.1"
  lxd_remote_port="8443"
  lxd_remote_password="${LXD_REMOTE_PASSWORD:-none}"
  ansible_requirements="requirements.yml"
  ansible_enable_profiler="true"
  ansible_errors_fatal="true"
  # for uploading
  minio_alias="remote"
  minio_username="${MINIO_USER}"
  minio_password="${MINIO_SECRET}"
  minio_host="minio.osshelp.ru"
  minio_bucket="ansible"
  export_name="${DRONE_REPO_NAME##ansible-}"
  release_directory="/tmp/release"
  release_file="${release_directory}/${export_name}.tar.gz"
  source_object="${release_file}"
  destination_prefix="pub/roles/"

  #ansible color output
  export ANSIBLE_FORCE_COLOR='true'
  export ANSIBLE_DISPLAY_SKIPPED_HOSTS='no'

  for var in "${!PLUGIN_@}"; do
    case "${var}" in
      PLUGIN_ACTION)               required_action="${PLUGIN_ACTION}" ;;
      PLUGIN_SCENARIO)             required_scenario="${PLUGIN_SCENARIO}" ;;
      PLUGIN_LXD_REMOTE_HOST)      lxd_remote_host="${PLUGIN_LXD_REMOTE_HOST}" ;;
      PLUGIN_LXD_REMOTE_PORT)      lxd_remote_port="${PLUGIN_LXD_REMOTE_PORT}" ;;
      PLUGIN_RELEASE_DIRECTORY)    release_directory="${PLUGIN_RELEASE_DIRECTORY}" ;;
      PLUGIN_ANSIBLE_REQUIREMENTS) ansible_requirements="${PLUGIN_ANSIBLE_REQUIREMENTS}" ;;
      PLUGIN_ANSIBLE_PROFILER)     ansible_enable_profiler="${PLUGIN_ANSIBLE_PROFILER}" ;;
      PLUGIN_ANSIBLE_STRATEGY)     : ;; # to avoid warning below
      PLUGIN_ANSIBLE_ERRORS_FATAL) ansible_errors_fatal="${PLUGIN_ANSIBLE_ERRORS_FATAL}" ;;
      PLUGIN_ANSIBLE_DISPLAY_SKIPPED) export ANSIBLE_DISPLAY_SKIPPED_HOSTS="${PLUGIN_ANSIBLE_DISPLAY_SKIPPED}" ;;
      PLUGIN_ANSIBLE_VAULT_PASSWORD) echo -n "$PLUGIN_ANSIBLE_VAULT_PASSWORD" > /tmp/vault_password.txt; export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault_password.txt ;;
      PLUGIN_MINIO_ALIAS)          minio_alias="${PLUGIN_MINIO_ALIAS}" ;;
      PLUGIN_MINIO_HOST)           minio_host="${PLUGIN_MINIO_HOST}" ;;
      PLUGIN_MINIO_BUCKET)         minio_bucket="${PLUGIN_MINIO_BUCKET}" ;;
      PLUGIN_UPLOAD_PREFIX)        destination_prefix="${PLUGIN_UPLOAD_PREFIX}" ;;
      PLUGIN_UPLOAD_AS)            export_name="${PLUGIN_UPLOAD_AS}" ;;
      PLUGIN_MINIO_DEBUG)          minio_debug="--debug" ;;
      PLUGIN_RELEASE_ALIAS)        release_alias="${PLUGIN_RELEASE_ALIAS}" ;;
      PLUGIN_DEBUG)                : ;; # to avoid warning below
      PLUGIN_*) show_warning "Setting $(echo "${var#PLUGIN_}" | tr '[:upper:]' '[:lower:]') does not exist. Will do nothing." ;;
    esac
  done

  # specially for Molecule
  export LC_ALL=C.UTF-8
  export LANG=C.UTF-8

  # selecting unique release id (tag vs short hash)
  test -n "${DRONE_TAG##v}" && {
    release_id="${DRONE_TAG##v}"
    release_major="${release_id%%.*}"
  }
  test -n "${DRONE_TAG##v}" || release_id="${DRONE_COMMIT:0:7}"

  # enabling profiling for tasks only
  test "${ansible_enable_profiler}" == "true" && \
    export ANSIBLE_CALLBACK_WHITELIST='profile_tasks,timer'

  test -n "${PLUGIN_ANSIBLE_STRATEGY}" && \
    export ANSIBLE_STRATEGY="${PLUGIN_ANSIBLE_STRATEGY}"

  # we should hang on any error
  # https://docs.ansible.com/ansible/latest/reference_appendices/config.html#any-errors-fatal
  export ANSIBLE_ANY_ERRORS_FATAL="${ansible_errors_fatal}"

  # we could need it later in custom tests with pylxd (connect to remote LXD)
  export lxd_remote_host
  export lxd_remote_port

  test -n "${PLUGIN_ANSIBLE_REQUIREMENTS}" -a ! -r "${PLUGIN_ANSIBLE_REQUIREMENTS}" && {
    show_error "File ${PLUGIN_ANSIBLE_REQUIREMENTS} with Ansible requirements is missing or isn't readable"
  }

  test "${required_action}" == "release" -o "${required_action}" == "test" && {
    export LXD_REMOTE_URL="https://${lxd_remote_host}:${lxd_remote_port}"

  }

  test "${required_action}" == "release" -o "${required_action}" == "upload" && {

    test -z "${minio_host}" -o -z "${minio_bucket}" && \
      show_error "You should set minio_host and minio_bucket in settings!"
    test -z "${minio_username}" -o -z "${minio_password}" && \
      show_error "You should set MINIO_USER and MINIO_SECRET in environment (from secrets)!"

    check_minio_access || \
      show_error "MinIO client can't access ${minio_host}/${minio_bucket}, re-check your settings"
  }

  test -z "${release_alias}" && generate_release_alias

  return 0
}

function run_molecule() {
  test -r "${ansible_requirements}" && \
    check_and_install_requirements

  # ugly hack for Molecule expectations (see https://github.com/ansible/molecule/issues/1567)
  directory_name="$(pwd)"
  test "${directory_name}" != "${DRONE_REPO_NAME}" && {
    ln -s "$(pwd)" "../${DRONE_REPO_NAME}"
    cd "../${DRONE_REPO_NAME}" || return 1
  }
  show_notice "Running Molecule"
  molecule test --scenario-name "${required_scenario}"
}

function run_linters() {
  test -r "${ansible_requirements}" && \
    check_and_install_requirements

  # ugly hack for Molecule expectations (see https://github.com/ansible/molecule/issues/1567)
  directory_name="$(pwd)"
  test "${directory_name}" != "${DRONE_REPO_NAME}" && {
    ln -s "$(pwd)" "../${DRONE_REPO_NAME}"
    cd "../${DRONE_REPO_NAME}" || return 1
  }
  show_notice "Running validation"
  molecule lint --scenario-name "${required_scenario}"
}

function check_and_install_requirements() {
  test -s "${ansible_requirements}" -a -r "${ansible_requirements}" && \
    show_notice "Downloading requirements from ${ansible_requirements}"
    ansible-galaxy install -r "${ansible_requirements}"
}

function add_lxd_remote() {
  local err=1
  test -z "${lxd_remote_host}" -o -z "${lxd_remote_port}" -o -z "${lxd_remote_password}" && \
    show_error "You should set LXD_REMOTE_HOST, LXD_REMOTE_PORT and LXD_REMOTE_PASSWORD"
  show_notice "Adding ${lxd_remote_host}:${lxd_remote_port} as LXD remote"
  test -x "$(command -v lxc)" && {
    lxc remote add "${lxd_remote_name}" "${lxd_remote_host}:${lxd_remote_port}" --password "${lxd_remote_password}" --accept-certificate && \
      lxc remote set-default "${lxd_remote_name}" && \
        err=0
    show_notice "Adding Ubuntu Minimal as LXD remote (see https://wiki.ubuntu.com/Minimal)"
    lxc remote add --protocol simplestreams ubuntu-minimal https://cloud-images.ubuntu.com/minimal/releases/
    show_notice "Adding OSSHelp public LXD server"
    lxc remote add --public --protocol lxd osshelp https://lxd.osshelp.ru:443
  }
  return "${err}"
}

function create_release_as_archive() {
  test -d "${release_directory}" || mkdir -p "${release_directory}"
  test -d "${release_directory}" && {
    show_notice "Creating release as ${release_file}"
    tar cfz "${release_file}" --exclude-vcs --exclude-vcs-ignores --exclude-backups --exclude './.*' --exclude '*.pyc' --exclude '__pycache__' --exclude 'molecule' .
    show_notice "Resulting archive details:"
    ls -lh "${release_file}"
  }
}

function check_minio_access() {
  read -r "MC_HOST_${minio_alias}" <<< "https://${minio_username}:${minio_password}@${minio_host}"
  export "MC_HOST_${minio_alias}"
  minio-client ${minio_debug} ls "${minio_alias}/${minio_bucket}" >/dev/null
}

function upload_to_minio() {
  local source=${1}; local target="${2}"; local upload_failed=0

  read -d ' ' -r -a source_objects <<< "$(eval 'ls -1 ${source}')"
  for source_object in "${source_objects[@]}"; do
    test -z "${source_object}" -o ! -r "${source_object}" && \
      show_error "Source ${source_object} doesn't exists or can't be readed"
  done

  show_notice "Uploading ${source} to ${minio_host}/${minio_bucket}/${target}"
  object_attributes="SOURCE=${DRONE_REPO_NAMESPACE:-none}/${DRONE_REPO_NAME:-none},BUILDED=${DRONE_BUILD_CREATED:-0},BUILD=${DRONE_BUILD_NUMBER:-42},RELEASE=${release_id}"
  upload_result=$(minio-client --json --quiet cp --attr "${object_attributes}" "${source}" "${minio_alias}/${minio_bucket}/${target}")
  total_results=$(jq <<< "${upload_result}" .status | wc -l)
  total_successes=$(jq <<< "${upload_result}" .status | grep -c '\"success\"')
  test "${total_successes:-foo}" == 0 && upload_failed=1
  test "${total_successes:-foo}" != "${total_results:-bar}" && upload_failed=1

  # happy end
  test "${upload_failed}" == 0 -a "${minio_host}" == "minio.osshelp.ru" -a "${minio_bucket}" == "ansible" && \
    show_notice "Role uploaded and should be available as https://oss.help/${minio_bucket}/${target}"

  return "${upload_failed}"
}
function copy_on_minio() {
  local source=${1}; local target="${2}"; local upload_failed=0

  minio-client stat "${minio_alias}/${minio_bucket}/${source}" >/dev/null 2>&1 || \
    show_error "Source ${source} doesn't exists or can't be readed"

  show_notice "Copying ${source} to ${target} within ${minio_host}/${minio_bucket}"
  object_attributes="SOURCE=${DRONE_REPO_NAMESPACE:-none}/${DRONE_REPO_NAME:-none},BUILDED=${DRONE_BUILD_CREATED:-0},BUILD=${DRONE_BUILD_NUMBER:-42},RELEASE=${release_id}"
  upload_result=$(minio-client --json --quiet cp --attr "${object_attributes}" "${minio_alias}/${minio_bucket}/${source}" "${minio_alias}/${minio_bucket}/${target}")
  total_results=$(jq <<< "${upload_result}" .status | wc -l)
  total_successes=$(jq <<< "${upload_result}" .status | grep -c '\"success\"')
  test "${total_successes:-foo}" == 0 && upload_failed=1
  test "${total_successes:-foo}" != "${total_results:-bar}" && upload_failed=1

  return "${upload_failed}"
}
function upload_release() {
  local release_upload_result=1; local aliases_upload_result=1; local major_upload_result=1; local destination_object; local upload_prefix

  # reduce number of objects in one subdirectory by splitting them
  upload_prefix=${export_name:0:1}

  destination_object="${destination_prefix}${upload_prefix}/${export_name}-${release_id}.tar.gz"

  test -r "${source_object}" && {
    show_notice "Uploading release from ${source_object}"
    upload_to_minio "${source_object}" "${destination_object}" && \
    release_upload_result=0
  }
  test -z "${release_alias}" && aliases_upload_result=0
  test -n "${release_alias}" && {
    release_as_alias="${destination_object/${release_id}/${release_alias}}"
    test "${release_upload_result}" -eq 0 -a "${destination_object}" != "${release_as_alias}" && {
      show_notice "Copying uploaded release as ${release_alias}"
      copy_on_minio "${destination_object}" "${release_as_alias}" && \
      aliases_upload_result=0
    }
  }
  test -z "${release_major}" && major_upload_result=0
  test -n "${release_major}" && {
    release_as_major="${destination_prefix}${upload_prefix}/${release_major}/${export_name}-${release_alias}.tar.gz"
    show_notice "Copying uploaded release as ${release_major}/${export_name}-${release_alias}"
    copy_on_minio "${destination_object}" "${release_as_major}" && \
    major_upload_result=0
  }

  test "${release_upload_result}" -eq 0 -a "${aliases_upload_result}" -eq 0 -a "${major_upload_result}" -eq 0 && \
    return 0 || return 1
}

function main() {
  test -z "$PLUGIN_LINTER_SKIP" -o -n "$PLUGIN_LINTER_FORCE" && { linters.sh || exit "$?"; }

  check_and_set_vars

  test "${required_action}" == "release" && {
    add_lxd_remote && \
    run_molecule && \
    create_release_as_archive && \
    upload_release
    build_failed=${?}
  }

  test "${required_action}" == "test" && {
    add_lxd_remote && \
    run_molecule
    build_failed=${?}
  }

  test "${required_action}" == "upload" && {
    run_linters && \
    create_release_as_archive && \
    upload_release
    build_failed=${?}
  }

}

main "${@}"
exit "${build_failed}"
