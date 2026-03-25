#!/bin/bash

# author: Shlomi Ben-David <shlomi.ben.david@gmail.com>
# description: This script used as an entrypoint for the k8s-ssh image
# version: 0.0.2
# modified: Fixed for containerd compatibility - use /host mount instead of /

set -o errexit
#set -o xtrace
umask 0077

# Host filesystem is mounted at /host
HOST_ROOT="/host"

# we need to make sure that this script runs with a root user
if [ `id -u` -ne 0 ] ; then
    echo "You must run this script as a root user"
    exit 1
fi

function restart_ssh_service(){
    if [[ "${restart_service}" == "yes" ]] ; then
        echo "Restarting SSH service"
        # Use nsenter to execute systemctl in the host's PID/mount namespace
        nsenter --target 1 --mount --uts --ipc --net --pid -- systemctl restart sshd.service
    fi
}

function update_ssh_public_keys(){
    current_md5=$(md5sum ${authorized_keys_file} 2>/dev/null | cut -d ' ' -f1 || echo "")
    new_md5=$(md5sum ${tmp_authorized_keys_file} | cut -d ' ' -f1)
    if [[ "${current_md5}" != "${new_md5}" ]] ; then
        echo "Updating SSH public keys"
        mv "${tmp_authorized_keys_file}" "${authorized_keys_file}"
    fi
}

function get_ssh_public_keys(){
    echo "Getting SSH public keys"
    [[ -e "${tmp_authorized_keys_file}" ]] && rm -f "${tmp_authorized_keys_file}"
    for key in $(find /mnt/keys -type f); do (cat ${key}; echo) >> "${tmp_authorized_keys_file}"; done
}

function modify_ssh_config(){
    echo "Modifying SSH config"
    restart_service="no"
    if [[ `grep ^PasswordAuthentication "${ssh_config_file}" | cut -d " " -f2` == "yes" ]] ; then
        sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "${ssh_config_file}"
        restart_service="yes"
    fi

    if [[ `grep -cE '#PubkeyAuthentication' "${ssh_config_file}"` -eq 1 ]] ; then
        sed -i 's/#PubkeyAuthentication/PubkeyAuthentication/' "${ssh_config_file}"
        restart_service="yes"
    fi

    restart_ssh_service
}

#### MAIN ####

# All paths now use /host prefix to access the host filesystem
ssh_dir="${HOST_ROOT}/root/.ssh"
tmp_authorized_keys_file="${ssh_dir}/authorized_keys_tmp"
authorized_keys_file="${ssh_dir}/authorized_keys"
ssh_config_file="${HOST_ROOT}/etc/ssh/sshd_config"

[[ ! -e "${ssh_dir}" ]] && mkdir -p "${ssh_dir}"

modify_ssh_config

while true
do
    echo "timestamp: `date +%m%d%y%H%M%S`"
    get_ssh_public_keys
    update_ssh_public_keys
    sleep 60s
done
