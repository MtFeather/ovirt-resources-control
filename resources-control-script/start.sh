#!/bin/bash
time="${1}"
/bin/sed -i s/OnUnitActiveSec=.*/OnUnitActiveSec=${time}m/g /etc/systemd/system/ovirt-resources-control.timer
/bin/systemctl daemon-reload

/bin/systemctl start analysis-vm-loading.service
/bin/systemctl enable analysis-vm-loading.service


/bin/systemctl start analysis-host-loading.service
/bin/systemctl enable analysis-host-loading.service

/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 172.26.0.253 "systemctl start analysis-iscsi-loading.service; systemctl enable analysis-iscsi-loading.service"

/bin/systemctl start ovirt-resources-control.service
/bin/systemctl enable ovirt-resources-control.service
/bin/systemctl start ovirt-resources-control.timer
/bin/systemctl enable ovirt-resources-control.timer
