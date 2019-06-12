#!/bin/bash
today=$( date '+%Y-%m-%d' )
yesterday=$( date --date='1 days ago' '+%Y-%m-%d' )
sql_dir="/gocloud/ovirt-ui-plugins/resources-control/resources-control-backup-sql"
vm_sql="${sql_dir}/vm_backup_${yesterday}.sql"
host_sql="${sql_dir}/host_backup_${yesterday}.sql"
iscsi_sql="${sql_dir}/iscsi_backup_${yesterday}.sql"

function _psql() {
        /opt/rh/rh-postgresql10/root/usr/bin/psql -U gocloud -c "${1}"
}

function _pg_dump() {
        /opt/rh/rh-postgresql10/root/usr/bin/pg_dump -U gocloud -t "${1}" --data-only --column-inserts > "${2}"
}

# 建立一張臨時的資料表，方便下一個備份的動作執行
_psql "CREATE TABLE backup_vm_loading (name varchar(40), cpu float8, mem float8, disk_read bigint, disk_write bigint, net_rx bigint, net_tx bigint, up_time timestamptz);"
_psql "CREATE TABLE backup_host_loading (name varchar(40), ip varchar(39), cpu_idle float8, net_rx bigint, net_tx bigint, up_time timestamptz);"
_psql "CREATE TABLE backup_iscsi_loading (read bigint, write bigint, up_time timestamptz);"

# 將大於一天的資料備份到另一張資料表，備份完把資料全刪除，過程中會把原始資料表鎖住，防止資料不一致！
_psql "BEGIN;
       INSERT INTO backup_vm_loading SELECT * FROM vm_loading WHERE up_time < '${today}';
       DELETE FROM vm_loading WHERE up_time < '${today}';
       INSERT INTO backup_host_loading SELECT * FROM host_loading WHERE up_time < '${today}';
       DELETE FROM host_loading WHERE up_time < '${today}';
       INSERT INTO backup_iscsi_loading SELECT * FROM iscsi_loading WHERE up_time < '${today}';
       DELETE FROM iscsi_loading WHERE up_time < '${today}';
       COMMIT;"

# 匯出資料庫
_pg_dump "backup_vm_loading" "${vm_sql}"
_pg_dump "backup_host_loading" "${host_sql}"
_pg_dump "backup_iscsi_loading" "${iscsi_sql}"

# 刪除臨時資料庫
_psql "DROP TABLE backup_vm_loading, backup_host_loading, backup_iscsi_loading;"

# 執行VACUUM FULL將資料庫刪除的空間釋出
_psql  "VACUUM FULL;"
       
