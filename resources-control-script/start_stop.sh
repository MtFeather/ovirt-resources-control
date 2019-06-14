#!/bin/bash
action="${1}"
min="${2}"
case "${action}" in
	"start")
		/bin/sed -i s/OnUnitActiveSec=.*/OnUnitActiveSec=${min}m/g /etc/systemd/system/ovirt-resources-control.timer
		/bin/systemctl daemon-reload
		
		/bin/systemctl enable --now analysis-vm-loading.service
		/bin/systemctl enable --now analysis-host-loading.service
		/bin/systemctl enable --now --host=iscsi analysis-iscsi-loading.service

		/bin/systemctl enable --now ovirt-resources-control.service
		/bin/systemctl enable --now ovirt-resources-control.timer
		;;
	"stop")
		/bin/systemctl disable --now analysis-vm-loading.service
		/bin/systemctl disable --now analysis-host-loading.service
		/bin/systemctl disable --now --host=iscsi analysis-iscsi-loading.service

		/bin/systemctl disable --now ovirt-resources-control.service
		/bin/systemctl disable --now ovirt-resources-control.timer
		;;
	*)
		echo "Not have this command."
		;;
esac
