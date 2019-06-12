#!/bin/bash
source ./config.sh
source ./function.sh
vms_xml="${basedir}/vms.xml"
disks_xml="${basedir}/disks.xml"

while true;
do
	_api "vms?search=status=up&follow=statistics,disk_attachments.disk,nics.statistics" "${vms_xml}"
	_api "disks?follow=statistics" "${disks_xml}"
	vm_num=$( _xpath "count(/vms/vm)" ${vms_xml} )
	for i in $( seq 1 ${vm_num} )
	do
		name=$( _xpath "/vms/vm[${i}]/name/text()" ${vms_xml} )
		echo "Name: ${name}"

		cores=$( _xpath "/vms/vm[${i}]/cpu/topology/cores/text()" "${vms_xml}" )
		sockets=$( _xpath "/vms/vm[${i}]/cpu/topology/sockets/text()" "${vms_xml}" )
		threads=$( _xpath "/vms/vm[${i}]/cpu/topology/threads/text()" "${vms_xml}" )
		vcpu=$(( ${cores}*${sockets}*${threads} ))
		cpu_total=$( _xpath "/vms/vm[${i}]/statistics/statistic[name[text()=\"cpu.current.total\"]]/values/value/datum/text()" "${vms_xml}" )
		cpu=$(echo "${cpu_total}" "${vcpu}" |awk '{printf ("%2.f", $1/$2)}')
		echo "CPU (%): ${cpu}"
		
		disk_id=$( _xpath "/vms/vm[${i}]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1/g' )
		disk_read=$( _xpath "//disk[@id=\"${disk_id}\"]/statistics/statistic[name[text()=\"data.current.read\"]]/values/value/datum/text()" "${disks_xml}" )
		disk_write=$( _xpath "//disk[@id=\"${disk_id}\"]/statistics/statistic[name[text()=\"data.current.write\"]]/values/value/datum/text()" "${disks_xml}" )
		echo "Disk Read (bytes/s): ${disk_read}"
		echo "Disk Write (bytes/s): ${disk_write}"

		net_rx=$( _xpath "/vms/vm[${i}]/nics/nic[1]/statistics/statistic[name[text()=\"data.current.rx\"]]/values/value/datum/text()" "${vms_xml}" )
		net_tx=$( _xpath "/vms/vm[${i}]/nics/nic[1]/statistics/statistic[name[text()=\"data.current.tx\"]]/values/value/datum/text()" "${vms_xml}" )
		echo "Network Reciver (bytes/s): ${net_rx}"
                echo "Network Transfer (bytes/s): ${net_tx}"
		_psql "INSERT INTO vm_loading (name, cpu, mem, disk_read, disk_write, net_rx, net_tx, up_time) VALUES ('${name}', ${cpu}, 0, ${disk_read}, ${disk_write}, ${net_rx}, ${net_tx}, now());"
		echo
	done
	sleep 10s
done
