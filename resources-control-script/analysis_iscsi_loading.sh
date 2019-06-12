#!/bin/bash
source ./config.sh

disk=$( df --output=source ${nfs_dir} |awk -F '/' 'NR>1{print $NF}' )

while true;
do
	sar -d -p  1 3  > ${sar_file}
	iscsi_write=$( cat ${sar_file} | grep ${disk} | awk '{print $5}' | tail -n 1 | awk -F "." '{print $1}' )
	iscsi_read=$( cat ${sar_file} | grep ${disk} | awk '{print $4}' | tail -n 1 | awk -F "." '{print $1}' )
	echo "Write: ${iscsi_write}"
	echo "Read: ${iscsi_read}"
	curl -X POST --data "write=${iscsi_write}&read=${iscsi_read}" http://172.26.0.254/ovirt-ui-plugins/resources-control/resources-control-resources/iscsi_insert.php
	echo
	sleep 10s
done
