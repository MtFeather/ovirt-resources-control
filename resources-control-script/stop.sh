#!/bin/bash
/bin/systemctl stop analysis-vm-loading.service
/bin/systemctl disable analysis-vm-loading.service
/bin/systemctl stop analysis-host-loading.service
/bin/systemctl disable analysis-host-loading.service

/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 172.26.0.253 "systemctl stop analysis-iscsi-loading.service; systemctl disable analysis-iscsi-loading.service"

/bin/systemctl stop ovirt-resources-control.timer
/bin/systemctl disable ovirt-resources-control.timer
