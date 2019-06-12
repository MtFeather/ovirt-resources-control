#!/bin/bash
source ./config.sh
source ./function.sh
hosts_xml="${basedir}/hosts.xml"
ovirtmgmt_id="00000000-0000-0000-0000-000000000009"

while true;
do
	_api "hosts?search=status=up&follow=statistics,nics.statistics" "${hosts_xml}"
	host_num=$( _xpath "count(/hosts/host)" "${hosts_xml}" )
	for i in $( seq 1 ${host_num} )
	do
		name=$( _xpath "/hosts/host[${i}]/name/text()" "${hosts_xml}" )
		echo "Name: ${name}"

		ip=$( _xpath "/hosts/host[${i}]/address/text()" "${hosts_xml}" )
		echo "IP: ${ip}"

		cpu_idle=$( _xpath "/hosts/host[${i}]/statistics/statistic[name[text()=\"cpu.current.idle\"]]/values/value/datum/text()" "${hosts_xml}" )
		echo "CPU Idle (%): ${cpu_idle}"

		[ ! -f "${basedir}/old_${name}_rx_file.txt" ] && echo "0" > ${basedir}/old_${name}_rx_file.txt
		[ ! -f "${basedir}/old_${name}_tx_file.txt" ] && echo "0" > ${basedir}/old_${name}_tx_file.txt
		total_net_rx=$( _xpath "/hosts/host[${i}]/nics/host_nic[network[@id=\"${ovirtmgmt_id}\"]]/statistics/statistic[name[text()=\"data.total.rx\"]]/values/value/datum/text()" "${hosts_xml}" )
		total_net_tx=$( _xpath "/hosts/host[${i}]/nics/host_nic[network[@id=\"${ovirtmgmt_id}\"]]/statistics/statistic[name[text()=\"data.total.tx\"]]/values/value/datum/text()" "${hosts_xml}" )
		old_net_rx=$( cat ${basedir}/old_${name}_rx_file.txt )
		old_net_tx=$( cat ${basedir}/old_${name}_tx_file.txt )
		net_rx=$( echo ${total_net_rx} ${old_net_rx} | awk '{printf("%2.f", ($1-$2)/1024/1024/2)}' )
		net_tx=$( echo ${total_net_tx} ${old_net_tx} | awk '{printf("%2.f", ($1-$2)/1024/1024/2)}' )
		echo ${total_net_rx} > ${basedir}/old_${name}_rx_file.txt
		echo ${total_net_tx} > ${basedir}/old_${name}_tx_file.txt
		echo "Network Reciver (bytes): ${net_rx}"
		echo "Network Transfer (bytes): ${net_tx}"
		_psql "INSERT INTO host_loading (name, ip, cpu_idle, net_rx, net_tx, up_time) VALUES ('${name}','${ip}', ${cpu_idle}, ${net_rx}, ${net_tx}, now());" 
	done
	echo
	sleep 10s
done
