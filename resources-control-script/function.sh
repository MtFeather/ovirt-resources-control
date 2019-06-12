#!/bin/bash
function _session() {
	[ ! -f ${session_file} ] && touch ${session_file}
	bearer=$( cat ${session_file} )
	status_code=$( curl --output /dev/null --silent --write-out "%{http_code}\n" --insecure --header "Authorization: Bearer ${bearer}" https://localhost/ovirt-engine/api )
	if [ ${status_code} -eq 401 ]; then
		session=$( curl \
			   --insecure \
			   --silent \
			   --header "Content-Type: application/x-www-form-urlencoded" \
			   --header "Accept: application/json" \
			   --data "grant_type=password&scope=ovirt-app-api&username=${user}&password=${password}" \
			   https://localhost/ovirt-engine/sso/oauth/token | sed 's/.*"access_token":"\([^"]*\)".*/\1/g' )
		echo ${session} > ${session_file}
	fi
}
function _api() {
	_session
	bearer=$( cat ${session_file} )
	curl \
	--insecure \
	--header "Accept: application/xml" \
	--header "Authorization: Bearer ${bearer}" \
	--header "Prefer: persistent-auth" \
	"${url}/${1}" 2>/dev/null > "${2}"
}

function _xpath() {
	xmllint --xpath "${1}" ${2}
}

function _psql() {
	/opt/rh/rh-postgresql10/root/usr/bin/psql -U gocloud -At -F " " -c "${1}" 
}

function _pg_dump() {
	/opt/rh/rh-postgresql10/root/usr/bin/pg_dump -U gocloud -t "${1}" --data-only --column-inserts > "${2}"
}

function _ssh() {
	/usr/bin/expect -c "
	spawn ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 ${1} \"${2}\";
	expect \"name:\";
	send \"vdsm@ovirt\r\";
	expect \"password:\";
	send \"shibboleth\r\";
	interact" 
}
