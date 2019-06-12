#!/bin/bash
# Directory Path
resources_dir="/dev/shm/ovirt-cache/"
basedir="${resources_dir}/analysis"
session_file="${resources_dir}/session.txt"
old_host_rx_file="${basedir}/old_host_rx.txt"
old_host_tx_file="${basedir}/old_host_tx.txt"
sar_file="${basedir}/sar_file.txt"
nfs_dir="/gocloud_fs"

# Command Path
psql="/opt/rh/rh-postgresql10/root/usr/bin/psql -U gocloud"

# Ovirt REST API INFO
url="https://localhost/ovirt-engine/api"
user="admin@internal"
password="password"

[ ! -d ${basedir} ] && mkdir -p ${basedir}
[ ! -d ${resources_dir} ] && mkdir ${resources_dir}
