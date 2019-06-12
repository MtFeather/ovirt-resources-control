#!/bin/bash
source ./config.sh
source ./function.sh
IFS_old=$IFS
iscsi_domains_xml="${resources_dir}/iscsi_domains.xml"
hosts_xml="${resources_dir}/hosts.xml"
hosts_sql="${resources_dir}/hosts.sql"
vms_xml="${resources_dir}/vms.xml"
limited_sql="${resources_dir}/limited.sql"
vm_net_high_load_sql="${resources_dir}/vm_net_high_load.sql"
domblklist_txt="${resources_dir}/domblklist.txt"

resources_rows=( `_psql "SELECT cpu_utilization,iscsi_utilization,iscsi_write,iscsi_read,vm_max_disk_write,vm_max_disk_read,vm_limit_disk_write,vm_limit_disk_read,net_utilization,net_rx,net_tx,vm_net_rx,vm_net_tx FROM resources_policy;"` )
cpu_utilization=${resources_rows[0]}
iscsi_utilization=${resources_rows[1]}
iscsi_write=${resources_rows[2]}
iscsi_read=${resources_rows[3]}
vm_max_disk_write=$(( ${resources_rows[4]}*1024*1024 ))
vm_max_disk_read=$(( ${resources_rows[5]}*1024*1024 ))
vm_limit_disk_write=$(( ${resources_rows[6]}*1024*1024  ))
vm_limit_disk_read=$(( ${resources_rows[7]}*1024*1024  ))
net_utilization=${resources_rows[8]}
host_net_rx=${resources_rows[9]}
host_net_tx=${resources_rows[10]}
host_net_rx_high_load=$( echo "${host_net_rx}" "${net_utilization}" | awk '{printf ("%2.f",$1*($2/100)/1024/1024)}')
host_net_tx_high_load=$( echo "${host_net_tx}" "${net_utilization}" | awk '{printf ("%2.f",$1*($2/100)/1024/1024)}')
vm_net_limit_rx=${resources_rows[11]}
vm_net_limit_tx=${resources_rows[12]}

_api "storagedomains?search=external_status=ok%20type=nfs" "${iscsi_domains_xml}"
block_sizes=( `xmllint --xpath "//storage_domain[type[text()=\"data\"]]/block_size/text()" ${iscsi_domains_xml}` )
block_size=${block_sizes[0]}

iscsi_write_high_load=$( echo "${iscsi_write}" "${iscsi_utilization}" | awk '{printf ("%2.f",$1*($2/100))}')
iscsi_read_high_load=$( echo "${iscsi_read}" "${iscsi_utilization}" | awk '{printf ("%2.f",$1*($2/100))}')
iscsi_load_rows=( `_psql "SELECT AVG(read), AVG(write) FROM iscsi_loading WHERE AGE(now(), up_time) < '5 min';"` )
iscsi_write_load=$( echo "${iscsi_load_rows[1]} ${block_size}}" | awk '{printf("%d",$1*$2/1024/1024)}' )
iscsi_read_load=$( echo "${iscsi_load_rows[0]} ${block_size}" | awk '{printf("%d",$1*$2/1024/1024)}' )
all_limited_count=$( _psql "SELECT count(name) FROM limited_vm;")

_api "hosts" "${hosts_xml}"
_psql "SELECT name,ip, CAST(AVG(net_rx) AS INT) AS net_rx,CAST(AVG(net_tx) AS INT) AS net_tx FROM host_loading WHERE AGE(now(), up_time) < '15 min' GROUP BY name,ip ORDER BY ip;" > ${hosts_sql}
hosts=$( xmllint --xpath "count(//host)" ${hosts_xml} )

_api "vms?search=status=up&follow=nics,disk_attachments.disk" "${vms_xml}"
vms_name=$( xmllint --shell ${vms_xml} <<< 'cat //vm/name/text()' | sed '/\/ > /d; /^ -/d' | sed "s/\(.*\)/'\1'/g" | sed ':a;N;$!ba;s/\n/,/g' )

_psql "SELECT v.name, v.disk_read, v.disk_write, l.limited_cpu, l.limited_disk_read, l.limited_disk_write, l.limited_net_rx, l.limited_net_tx, l.read_count, l.write_count FROM (SELECT name, CAST(AVG(disk_read) AS INT) AS disk_read, CAST(AVG(disk_write) AS INT) AS disk_write FROM vm_loading WHERE AGE(now(), up_time) < '15 min' AND name IN (${vms_name}) GROUP BY name) AS v LEFT JOIN (SELECT name, cpu AS limited_cpu, disk_read AS limited_disk_read, disk_write AS limited_disk_write, net_rx AS limited_net_rx, net_tx AS limited_net_tx, read_count, write_count FROM limited_vm) AS l ON v.name=l.name;" > ${limited_sql}
vms=$( wc -l ${limited_sql} | cut -d " "  -f 1 )
################################Start detect cpu statistics#################################
echo "Detect cpu statistics..."
for host in $(seq 1 ${hosts})
do
	IFS=${IFS_old}
	host_name=$( xmllint --xpath "//host[${host}]/name/text()" ${hosts_xml} )
	host_address=$( xmllint --xpath "//host[${host}]/address/text()" ${hosts_xml} )
	cores=$(xmllint --xpath "//host[${host}]/cpu/topology/cores/text()" ${hosts_xml} )
	threads=$(xmllint --xpath "//host[${host}]/cpu/topology/threads/text()" ${hosts_xml} )
	sockets=$(xmllint --xpath "//host[${host}]/cpu/topology/sockets/text()" ${hosts_xml} )
	all_threads=$(( ${cores}*${threads}*${sockets} ))
	retain_threads=$(( all_threads-2 ))
	host_cpu_high_load=$( echo "${retain_threads} ${all_threads} ${cpu_utilization}" | awk '{printf("%d",($1/$2)*$3)}' )
	one_thread_high_load=$( echo "${all_threads}" | awk '{printf("%d",100/$1)}' )
	cpu_idle=$( _psql "SELECT CAST(AVG(cpu_idle) AS INT) FROM host_loading WHERE AGE(now(), up_time) < '5 min' AND name='${host_name}' GROUP BY name;" )
	host_cpu=$(( 100-${cpu_idle} ))
	echo "CPU_load: ${host_cpu}, CPU_high_load: ${host_cpu_high_load}"
	if [ ${host_cpu} -gt ${host_cpu_high_load} ]; then
		echo "${host_name} cpu is high load status."
                echo "Now searching for high load vm."
		vm_num=$( xmllint --xpath "//host[${host}]/summary/active/text()" ${hosts_xml} )
		echo "${host_name} ${host_address} ${cores}*${threads}*${sockets} ${all_threads} ${high_load} ${one_thread_high_load} ${cpu} ${vm_num}"
		if [ ${vm_num} -gt 1 ]; then
			vm_names=$( xmllint --shell ${vms_xml} <<< "cat //vm[display/address[text()='${host_address}']]/name/text()" | sed '/\/ > /d; /^ -/d' )
			for name in ${vm_names}
			do
				vm_cpu_load=$( _psql "SELECT CAST(AVG(cpu) AS INT) FROM vm_loading WHERE name='${name}' AND AGE(now(), up_time) < '30 min' GROUP BY name;" )
				if [ ${vm_cpu_load} -gt ${one_thread_high_load} ]; then
					limited_cpu=$( _psql "SELECT cpu FROM limited_vm WHERE name='${name}';" )
					if [ "${limited_cpu}" == "" ]; then
						echo "${name} cpu(${vm_load}%) on lock."
						vm_cores=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/cores/text()" ${vms_xml} )
						vm_threads=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/threads/text()" ${vms_xml} )
						vm_sockets=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/sockets/text()" ${vms_xml} )
						vm_vcpus=$(( ${vm_cores}*${vm_threads}*${vm_sockets} ))
						for vcpu in $(seq 0 $(( ${vm_vcpus}-1 )))
						do
							_ssh "${host_address}" "virsh vcpupin ${name} ${vcpu} 1" &>/dev/null
						done
						_psql "INSERT INTO limited_vm (name,cpu,disk_read,disk_write,net_rx,net_tx,read_count,write_count) VALUES ('${name}',1,0,0,0,0,0,0);"
					elif [ "${limited_cpu}" -eq 0  ]; then
						echo "${name} cpu(${vm_load}%) on lock."
						vm_cores=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/cores/text()" ${vms_xml} )
						vm_threads=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/threads/text()" ${vms_xml} )
						vm_sockets=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/sockets/text()" ${vms_xml} )
						vm_vcpus=$(( ${vm_cores}*${vm_threads}*${vm_sockets} ))
						for vcpu in $(seq 0 $(( ${vm_vcpus}-1 )))
						do
							_ssh "${host_address}" "virsh vcpupin ${name} ${vcpu} 1" &>/dev/null
						done
						_psql "UPDATE limited_vm SET cpu=1 WHERE name='${name}';"
						echo "${name} ${vm_load} ${vm_vcpus}"

					fi
				fi
			done
		fi
	elif [ "${host_cpu}" -lt "${host_cpu_high_load}" ]; then
                echo "${host_name} cpu is low load status."
                echo "Now searching vm and unload."
                IFS=$'\n'
		host_vm_name=$( xmllint --shell ${vms_xml} <<< "cat //vm[display/address[text()='${host_address}']]/name/text()" | sed '/\/ > /d; /^ -/d' | sed "s/\(.*\)/'\1'/g" | sed ':a;N;$!ba;s/\n/,/g' )
                limited_vms=( `_psql "SELECT name,cpu,disk_read,disk_write,net_rx,net_tx FROM limited_vm WHERE name IN (${host_vm_name});"` )
		all_threads=$(( ${all_threads}-1 ))
                for i in $(seq 0 $(( ${#limited_vms[@]} - 1)) )
                do
                        IFS=${IFS_old}
                        row=( ${limited_vms[${i}]} )
                        name=${row[0]}
                        limited_cpu=${row[1]}
                        limited_read=${row[2]}
                        limited_write=${row[3]}
                        limited_rx=${row[4]}
                        limited_tx=${row[5]}
                        if [ "${limited_cpu}" -ne 0 ] && [ "${limited_read}" -eq 0 ] && [ "${limited_write}" -eq 0 ] && [ "${limited_rx}" -eq 0 ] && [ "${limited_tx}" -eq 0 ]; then
                                echo "VM ${name} cpu is unlock."
				vm_cores=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/cores/text()" ${vms_xml} )
				vm_threads=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/threads/text()" ${vms_xml} )
				vm_sockets=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/sockets/text()" ${vms_xml} )
				vm_vcpus=$(( ${vm_cores}*${vm_threads}*${vm_sockets} ))
				for vcpu in $( seq 0 $(( ${vm_vcpus}-1 ))  )
				do
					_ssh "${host_address}" "virsh vcpupin ${name} ${vcpu} 0-${all_threads}" &>/dev/null
				done
                                _psql "DELETE FROM limited_vm WHERE name='${name}';"
                        elif [ "${limited_cpu}" -ne 0 ]; then
                                echo "VM ${name} cpu is unlock."
				vm_cores=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/cores/text()" ${vms_xml} )
				vm_threads=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/threads/text()" ${vms_xml} )
				vm_sockets=$(xmllint --xpath "//vm[name[text()='${name}']]/cpu/topology/sockets/text()" ${vms_xml} )
				vm_vcpus=$(( ${vm_cores}*${vm_threads}*${vm_sockets} ))
				for vcpu in $( seq 0 $(( ${vm_vcpus}-1 )) )
				do
					_ssh "${host_address}" "virsh vcpupin ${name} ${vcpu} 0-${all_threads}" &>/dev/null
				done
                                _psql "UPDATE limited_vm SET cpu=0 WHERE name='${name}';"
                        fi
                done
	fi
done
echo "ok."
#################################End detect cpu statistics##################################
echo "----------------------------------------------------"
############################Start detect network rx statistics##############################
echo "Detect network rx statistics..."
for host in $(seq 1 ${hosts})
do
	IFS=${IFS_old}
	row=( `sed -n "${host}p" ${hosts_sql}` )
	host_name=${row[0]}
	host_address=${row[1]}
	host_net_rx=${row[2]}
	host_vm_name=$( xmllint --shell ${vms_xml} <<< "cat //vm[display/address[text()='${host_address}']]/name/text()" | sed '/\/ > /d; /^ -/d' | sed "s/\(.*\)/'\1'/g" | sed ':a;N;$!ba;s/\n/,/g' )
	echo "HOST_net_rx: ${host_net_rx}, HOST_net_rx_high_load: ${host_net_rx_high_load}"
	if [ "${host_net_rx}" -gt "${host_net_rx_high_load}" ]; then
		echo "${host_name} network rx speed is high load status."
	        echo "Now searching for high load vm."
		_psql "SELECT name,CAST(AVG(net_rx) AS INT) AS net_rx ,CAST(AVG(net_tx) AS INT) AS net_tx FROM vm_loading WHERE AGE(now(), up_time) < '15 min' AND name IN (${host_vm_name}) AND net_rx > 10000000 GROUP BY name;" > ${vm_net_high_load_sql}
		vm_net_rx_high_load_num=$( wc -l ${vm_net_high_load_sql} | cut -d " "  -f 1 )
		if [ ${vm_net_rx_high_load_num} -gt 0 ]; then
			limit_speed=$( echo "${vm_net_limit_rx} ${vm_net_rx_high_load_num}" | awk '{printf ("%d",($1/$2)/2)}' )
			for i in $(seq 1 ${vm_net_rx_high_load_num})
			do
				high_row=( `sed -n "${i}p" ${vm_net_high_load_sql}` )
				name=${high_row[0]}
				check=$( _psql "SELECT net_rx FROM limited_vm WHERE name='${name}';" )
				if [ "${check}" == "" ]; then
					echo "${name} network rx on lock."
					mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
					_ssh "${host_address}" "virsh domiftune ${name} ${mac} --inbound ${limit_speed}" &>/dev/null
					_psql "INSERT INTO limited_vm (name,cpu,disk_read,disk_write,net_rx,net_tx,read_count,write_count) VALUES ('${name}',0,0,0,${limit_speed},0,0,0);"
	                        elif [ "${check}" -eq 0  ]; then
					echo "${name} network rx on lock."
					mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
					_ssh "${host_address}" "virsh domiftune ${name} ${mac} --inbound ${limit_speed}" &>/dev/null
					_psql "UPDATE limited_vm SET net_rx=${limit_speed} WHERE name='${name}';"
				fi
			done
		fi
	elif [ "${host_net_rx}" -lt "${host_net_rx_high_load}" ]; then
        	echo "${host_name} network rx speed is low load status."
        	echo "Now searching vm and unload."
        	IFS=$'\n'
        	limited_vms=( `_psql "SELECT name,cpu,disk_read,disk_write,net_rx,net_tx FROM limited_vm WHERE name IN (${host_vm_name});"` )
        	for i in $(seq 0 $(( ${#limited_vms[@]} - 1)) )
        	do
        	        IFS=${IFS_old}
        	        row=( ${limited_vms[${i}]} )
        	        name=${row[0]}
        	        limited_cpu=${row[1]}
        	        limited_read=${row[2]}
        	        limited_write=${row[3]}
        	        limited_rx=${row[4]}
        	        limited_tx=${row[5]}
        	        if [ "${limited_cpu}" -eq 0 ] && [ "${limited_read}" -eq 0 ] && [ "${limited_write}" -eq 0 ] && [ "${limited_rx}" -ne 0 ] && [ "${limited_tx}" -eq 0 ]; then
        	                echo "VM ${name} network rx is unlock."
				mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
				_ssh "${host_address}" "virsh domiftune ${name} ${mac} --inbound 0" &>/dev/null
        	                _psql "DELETE FROM limited_vm WHERE name='${name}';"
        	        elif [ "${limited_rx}" -ne 0 ]; then
        	                echo "VM ${name} disk read is unlock."
				mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
				_ssh "${host_address}" "virsh domiftune ${name} ${mac} --inbound 0" &>/dev/null
        	                _psql "UPDATE limited_vm SET net_rx=0 WHERE name='${name}';"
        	        fi
        	done
	fi
done
echo "ok."
#############################End detect network rx statistics###############################
echo "----------------------------------------------------"
############################Start detect network tx statistics##############################
echo "Detect network tx statistics..."
for host in $(seq 1 ${hosts})
do
	IFS=${IFS_old}
	row=( `sed -n "${host}p" ${hosts_sql}` )
	host_name=${row[0]}
	host_address=${row[1]}
	host_net_tx=${row[3]}
	host_vm_name=$( xmllint --shell ${vms_xml} <<< "cat //vm[display/address[text()='${host_address}']]/name/text()" | sed '/\/ > /d; /^ -/d' | sed "s/\(.*\)/'\1'/g" | sed ':a;N;$!ba;s/\n/,/g' )
	echo "HOST_net_tx: ${host_net_tx}, HOST_net_tx_high_load: ${host_net_tx_high_load}"
	if [ "${host_net_tx}" -gt "${host_net_tx_high_load}" ]; then
		echo "${host_name} network tx speed is high load status."
	        echo "Now searching for high load vm."
		_psql "SELECT name,CAST(AVG(net_rx) AS INT) AS net_rx ,CAST(AVG(net_tx) AS INT) AS net_tx FROM vm_loading WHERE AGE(now(), up_time) < '15 min' AND name IN (${host_vm_name}) AND net_tx > 10000000 GROUP BY name;" > ${vm_net_high_load_sql}
		vm_net_tx_high_load_num=$( wc -l ${vm_net_high_load_sql} | cut -d " "  -f 1 )
		if [ ${vm_net_tx_high_load_num} -gt 0 ]; then
			limit_speed=$( echo "${vm_net_limit_tx} ${vm_net_tx_high_load_num}" | awk '{printf ("%d",($1/$2)/2)}' )
			for i in $(seq 1 ${vm_net_tx_high_load_num})
			do
				high_row=( `sed -n "${i}p" ${vm_net_high_load_sql}` )
				name=${high_row[0]}
				limited_tx=$( grep "${name}" ${limited_sql} | awk '{print $8}')
				check=$( _psql "SELECT net_tx FROM limited_vm WHERE name='${name}';" )
				if [ "${check}" == "" ]; then
					echo "${name} network tx on lock."
					mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
					_ssh "${host_address}" "virsh domiftune ${name} ${mac} --outbound ${limit_speed}" &>/dev/null
					_psql "INSERT INTO limited_vm (name,cpu,disk_read,disk_write,net_rx,net_tx,read_count,write_count) VALUES ('${name}',0,0,0,0,${limit_speed},0,0);"
	                        elif [ "${check}" -eq 0  ]; then
					echo "${name} network tx on lock."
					mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
					_ssh "${host_address}" "virsh domiftune ${name} ${mac} --outbound ${limit_speed}" &>/dev/null
                        	        _psql "UPDATE limited_vm SET net_tx=${limit_speed} WHERE name='${name}';"
                        	fi
			done
		fi
	elif [ "${host_net_tx}" -lt "${host_net_tx_high_load}" ]; then
        	echo "${host_name} network tx speed is low load status."
        	echo "Now searching vm and unload."
        	IFS=$'\n'
        	limited_vms=( `_psql "SELECT name,cpu,disk_read,disk_write,net_rx,net_tx FROM limited_vm WHERE name IN (${host_vm_name});"` )
        	for i in $(seq 0 $(( ${#limited_vms[@]} - 1)) )
        	do
        	        IFS=${IFS_old}
        	        row=( ${limited_vms[${i}]} )
        	        name=${row[0]}
        	        limited_cpu=${row[1]}
        	        limited_read=${row[2]}
        	        limited_write=${row[3]}
        	        limited_rx=${row[4]}
        	        limited_tx=${row[5]}
        	        if [ "${limited_cpu}" -eq 0 ] && [ "${limited_read}" -eq 0 ] && [ "${limited_write}" -eq 0 ] && [ "${limited_rx}" -eq 0 ] && [ "${limited_tx}" -ne 0 ]; then
        	                echo "VM ${name} network tx is unlock."
				mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
				_ssh "${host_address}" "virsh domiftune ${name} ${mac} --outbound 0" &>/dev/null
        	                _psql "DELETE FROM limited_vm WHERE name='${name}';"
        	        elif [ "${limited_tx}" -ne 0 ]; then
        	                echo "VM ${name} disk read is unlock."
				mac=$( xmllint --xpath "//vm[name[text()='${name}']]/nics/nic[name[text()='nic1']]/mac/address/text()" ${vms_xml} )
				_ssh "${host_address}" "virsh domiftune ${name} ${mac} --outbound 0" &>/dev/null
        	                _psql "UPDATE limited_vm SET net_tx=0 WHERE name='${name}';"
        	        fi
        	done
	fi
done
IFS=${IFS_old}
echo "ok."
#############################End detect network tx statistics###############################
echo "----------------------------------------------------"
##########################Start detect ISCSI disk read statistics###########################
echo "Detect ISCSI disk read statistics..."
echo "ISCSI_read: ${iscsi_read_load}, ISCSI_read_high_load: ${iscsi_read_high_load}"
if [ "${iscsi_read_load}" -gt "${iscsi_read_high_load}" ]; then
	echo "ISCSI disk read speed is high load status."
	echo "Now searching for high load vm."
	for vm in $(seq 1 ${vms})
	do 
		row=( `sed -n "${vm}p" ${limited_sql}` )
		name=${row[0]}
		disk_read=${row[1]}
		limited_read=${row[4]}
		limited_count=${row[8]}
		echo "VM: ${name}, read: ${disk_read} max: ${vm_max_disk_read}"
		[ "${limited_count}" == "" ] && limited_count=0
		if [ "${disk_read}" -gt "${vm_max_disk_read}" ] && [ "${limited_count}" -eq 0 ]; then
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			limit_speed=${vm_limit_disk_read}
			check=$( _psql "SELECT disk_read FROM limited_vm WHERE name='${name}';" )
			if [ "${check}" == "" ]; then
				echo "${name} disk read on lock."
				_ssh "${address}" "virsh blkdeviotune ${name} ${target} --read-bytes-sec ${limit_speed}" &>/dev/null
				_psql "INSERT INTO limited_vm (name,cpu,disk_read,disk_write,net_rx,net_tx,read_count,write_count) VALUES ('${name}',0,${limit_speed},0,0,0,1,0);"
			elif [ "${check}" -eq 0 ]; then
				echo "${name} disk read on lock."
				_ssh "${address}" "virsh blkdeviotune ${name} ${target} --read-bytes-sec ${limit_speed}" &>/dev/null
				_psql "UPDATE limited_vm SET disk_read=${limit_speed}, read_count=1 WHERE name='${name}';"
			fi
		elif [ "${limited_count}" -gt 0 ] && [ "${limited_count}" -lt 2 ]; then
			echo "${name} disk read on lock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
                        target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			limit_speed=$(( ${limited_read}/2 ))
			limit_count=$(( ${limited_count}+1 ))
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --read-bytes-sec ${limit_speed}" &>/dev/null
			_psql "UPDATE limited_vm SET disk_read=${limit_speed}, read_count=${limit_count} WHERE name='${name}';"
		fi
	done 
elif [ "${iscsi_read_load}" -lt "${iscsi_read_high_load}" ] && [ "${all_limited_count}" -gt 0 ]; then
	echo "ISCSI disk read speed is low load status."
	echo "Now searching vm and unload."
	IFS=$'\n'
	limited_vms=( `_psql "SELECT name,cpu,disk_read,disk_write,net_rx,net_tx FROM limited_vm;"` )
	for i in $(seq 0 $(( ${#limited_vms[@]} - 1)) )
        do
		IFS=${IFS_old}
                row=( ${limited_vms[${i}]} )
                name=${row[0]}
		limited_cpu=${row[1]}
		limited_read=${row[2]}
		limited_write=${row[3]}
		limited_rx=${row[4]}
		limited_tx=${row[5]}
		if [ "${limited_cpu}" -eq 0 ] && [ "${limited_read}" -ne 0 ] && [ "${limited_write}" -eq 0 ] && [ "${limited_rx}" -eq 0 ] && [ "${limited_tx}" -eq 0 ]; then
			echo "VM ${name} disk read is unlock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --read-bytes-sec 0" &>/dev/null
			_psql "DELETE FROM limited_vm WHERE name='${name}';"
		elif [ "${limited_read}" -ne 0 ]; then
			echo "VM ${name} disk read is unlock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --read-bytes-sec 0" &>/dev/null
			_psql "UPDATE limited_vm SET disk_read=0,read_count=0 WHERE name='${name}';"
		fi
	done
fi
IFS=${IFS_old}
echo "ok."
###########################End detect ISCSI disk read statistics############################
echo "----------------------------------------------------"
##########################Start detect ISCSI disk write statistics##########################
echo "Detect ISCSI disk write statistics..."
echo "ISCSI_write: ${iscsi_write_load}, ISCSI_write_high_load: ${iscsi_write_high_load}"
if [ "${iscsi_write_load}" -gt "${iscsi_write_high_load}" ]; then
	echo "ISCSI disk write speed is high load status."
	echo "Now searching for high load vm."
	for vm in $(seq 1 ${vms})
	do 
		row=( `sed -n "${vm}p" ${limited_sql}` )
		name=${row[0]}
		disk_write=${row[2]}
		limited_write=${row[5]}
		limited_count=${row[9]}
		echo "VM: ${name}, write: ${disk_write} max: ${vm_max_disk_write}"
		[ "${limited_count}" == "" ] && limited_count=0
		if [ "${disk_write}" -gt "${vm_max_disk_write}" ] && [ "${limited_count}" -eq 0 ]; then
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			limit_speed=${vm_limit_disk_write}
			check=$( _psql "SELECT disk_write FROM limited_vm WHERE name='${name}';" )
			if [ "${check}" == "" ]; then
				echo "${name} disk write on lock."
				_ssh "${address}" "virsh blkdeviotune ${name} ${target} --write-bytes-sec ${limit_speed}" &>/dev/null
				_psql "INSERT INTO limited_vm (name,cpu,disk_read,disk_write,net_rx,net_tx,read_count,write_count) VALUES ('${name}',0,0,${limit_speed},0,0,0,1);"
			elif [ "${check}" -eq 0 ]; then
				echo "${name} disk write on lock."
				_ssh "${address}" "virsh blkdeviotune ${name} ${target} --write-bytes-sec ${limit_speed}" &>/dev/null
				_psql "UPDATE limited_vm SET disk_write=${limit_speed}, write_count=1 WHERE name='${name}';"
			fi
		elif [ "${limited_count}" -gt 0 ] && [ "${limited_count}" -lt 2 ]; then
			echo "${name} disk write on lock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
                        target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			limit_speed=$(( ${limited_write}/2 ))
			limit_count=$(( ${limited_count}+1 ))
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --write-bytes-sec ${limit_speed}" &>/dev/null
			_psql "UPDATE limited_vm SET disk_write=${limit_speed}, write_count=${limit_count} WHERE name='${name}';"
		fi
	done 
elif [ "${iscsi_write_load}" -lt "${iscsi_write_high_load}" ] && [ "${all_limited_count}" -gt 0 ]; then
	echo "ISCSI disk write speed is low load status."
	echo "Now searching vm and unload."
	IFS=$'\n'
	limited_vms=( `_psql "SELECT name,cpu,disk_read,disk_write,net_rx,net_tx FROM limited_vm;"` )
	for i in $(seq 0 $(( ${#limited_vms[@]} - 1)) )
        do
		IFS=${IFS_old}
                row=( ${limited_vms[${i}]} )
                name=${row[0]}
		limited_cpu=${row[1]}
		limited_read=${row[2]}
		limited_write=${row[3]}
		limited_rx=${row[4]}
		limited_tx=${row[5]}
		if [ "${limited_cpu}" -eq 0 ] && [ "${limited_read}" -eq 0 ] && [ "${limited_write}" -ne 0 ] && [ "${limited_rx}" -eq 0 ] && [ "${limited_tx}" -eq 0 ]; then
			echo "VM ${name} disk write is unlock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --write-bytes-sec 0" &>/dev/null
			_psql "DELETE FROM limited_vm WHERE name='${name}';"
		elif [ "${limited_write}" -ne 0 ]; then
			echo "VM ${name} disk write is unlock."
                        address=$( xmllint --xpath "//vm[name[text()='${name}']]/display/address/text()" ${vms_xml} )
                        disk_id=$( xmllint --xpath "//vm[name[text()='${name}']]/disk_attachments/disk_attachment[1]/disk/@id" ${vms_xml} | sed 's/ id="\([^"]*\)"/\1 /g' )
			_ssh "${address}" "virsh domblklist ${name}" > ${domblklist_txt}
			target=$( cat ${domblklist_txt} | grep ${disk_id} | awk '{print $1}')
			_ssh "${address}" "virsh blkdeviotune ${name} ${target} --write-bytes-sec 0" &>/dev/null
			_psql "UPDATE limited_vm SET disk_write=0,write_count=0 WHERE name='${name}';"
		fi
	done
fi
echo "ok."
###########################End detect ISCSI disk write statistics###########################
