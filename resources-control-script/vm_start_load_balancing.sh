#!/bin/bash
source ./config.sh
source ./function.sh
vm_id=${1}
hosts_name=()
hosts_score=()

start_vm_xml=$( _vm_xml "${vm_id}" )
start_vm_name=$( xmllint --xpath "//vm/name/text()" - <<< ${start_vm_xml} )
start_vm_cores=$( xmllint --xpath "//vm/cpu/topology/cores/text()" - <<< ${start_vm_xml} )
start_vm_sockets=$( xmllint --xpath "//vm/cpu/topology/sockets/text()" - <<< ${start_vm_xml} )
start_vm_threads=$( xmllint --xpath "//vm/cpu/topology/threads/text()" - <<< ${start_vm_xml} )
start_vm_vcpu=$(( ${start_vm_cores}*${start_vm_sockets}*${start_vm_threads} ))

hosts_xml=$( _hosts_xml )
host_num=$( xmllint --xpath "count(//host)" - <<< ${hosts_xml} )

for i in $( seq 1 ${host_num} )
do
	host_name=$( xmllint --xpath "//host[${i}]/name/text()" - <<< ${hosts_xml} )
        hosts_name+=("${host_name}")

	host_cores=$( xmllint --xpath "//host[${i}]/cpu/topology/cores/text()" - <<< ${hosts_xml} )
	host_sockets=$( xmllint --xpath "//host[${i}]/cpu/topology/sockets/text()" - <<< ${hosts_xml} )
	host_threads=$( xmllint --xpath "//host[${i}]/cpu/topology/threads/text()" - <<< ${hosts_xml} )
	#host_speed=$( xmllint --xpath "//host[${i}]/cpu/speed/text()" - <<< ${hosts_xml} )
	host_cores_all=$(( ${host_cores}*${host_sockets} ))
	host_cpu=$( xmllint --xpath "//host[${i}]/cpu/name/text()" - <<< ${hosts_xml} )
        host_freq=$( echo ${host_cpu} | sed -e 's/.*@ \(.*\)GHz/\1/' )
	host_speed=$( echo "${host_freq} 1000" | awk '{ printf "%d" ,$1*$2}' )

	host_vms=$( _host_vms "${host_name}" )
	
	vm_vcpu_all="0"
	vm_num=$( xmllint --xpath "count(//vm)" - <<< ${host_vms} )
	for j in $( seq 1 ${vm_num} )
	do
		vm_cores=$( xmllint --xpath "//vm[${j}]/cpu/topology/cores/text()" - <<< ${host_vms} )
		vm_sockets=$( xmllint --xpath "//vm[${j}]/cpu/topology/sockets/text()" - <<< ${host_vms} )
		vm_threads=$( xmllint --xpath "//vm[${j}]/cpu/topology/threads/text()" - <<< ${host_vms} )
		vm_vcpu=$(( ${vm_cores}*${vm_sockets}*${vm_threads} ))
		vm_vcpu_all=$(( ${vm_vcpu_all}+${vm_vcpu} ))
	done
	
	cpu_overcommiting=$( echo "scale=2; ${vm_vcpu_all}/${host_cores_all}" | bc )

	var=$(awk 'BEGIN{ print "'${cpu_overcommiting}'" < "1" }')
	if [ "${var}" -eq 1 ]; then
		host_score=$(( ${host_speed} * ${start_vm_vcpu} ))
	elif [ "${host_threads}" -gt 1  ]; then
		host_score=$( echo "(${host_speed}*${start_vm_vcpu}*1.3)/${cpu_overcommiting}" | bc )
	else
		host_score=$( echo "(${host_speed}*${start_vm_vcpu})/${cpu_overcommiting}" | bc )
	fi

	hosts_score+=("${host_score}")
	echo "${host_name} ${host_cores_all} ${host_speed} ${vm_num} ${vm_vcpu_all} ${cpu_overcommiting} ${host_score}"
done

if [ ${#hosts_score[@]} -ne 0 ]; then
	arr=(`tr ' ' '\n' <<<${hosts_score[@]} | cat -n | sort -k2,2nr | head -n1`)
	index=$(( ${arr[0]}-1 ))
	score=${arr[1]}
	_placement_policy ${vm_id} ${hosts_name[${index}]} &> /dev/null
	_vm_start ${vm_id} &> /dev/null
	echo "${start_vm_name} start on ${hosts_name[${index}]}"
fi
