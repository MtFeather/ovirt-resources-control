<?php
function getVmList() {
  require('require/dbconfig.php');
  $requestData = $_REQUEST;
  $vm_names = $_POST["vm_names"];
  $vms = $_POST["vms"];
  if (!empty($vm_names) && !empty($vms)) {
    try {
      $conn = new PDO("pgsql:host=$host;dbname=$dbname", $user, $password);
      $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
      $stmt = $conn->prepare(" SELECT name,CAST(AVG(cpu) AS INT) AS cpu, CAST(AVG(disk_read) AS INT) AS disk_read, CAST(AVG(disk_write) AS INT) AS disk_write, CAST(AVG(net_rx) AS INT) AS net_rx, CAST(AVG(net_tx) AS INT) AS net_tx FROM vm_loading WHERE AGE(now(), up_time) < '5 min' AND name IN (${vm_names}) GROUP BY name ORDER BY name;");
      $stmt->execute();
      $totalData = $stmt->rowCount();
      $totalFiltered = $totalData;
      $data = array();
      while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        foreach($vms as $vm) {
          if ($vm['name'] == $row['name']) {
            $host = $vm['host'];
            break;
          }
        }
        $nestedData=array();
        $nestedData['name'] = $row['name'];
        $nestedData['host'] = $host;
        $nestedData['cpu'] = $row['cpu'];
        $nestedData['disk_read'] = $row['disk_read'];
        $nestedData['disk_write'] = $row['disk_write'];
        $nestedData['net_rx'] = $row['net_rx'];
        $nestedData['net_tx'] = $row['net_tx'];
        $data[] = $nestedData;
      }
      $json_data = array(
        "draw" => intval($requestData['draw']),
        "recordsTotal" => intval($totalData),
        "recordsFiltered" => intval($totalFiltered),
        "data" => $data
      );
      echo json_encode($json_data);
    }
    catch(PDOException $e) {
      echo "Error: " . $e->getMessage();
    }
    $conn = null;
  }
}

function getPolicys() {
  require('require/dbconfig.php');
  try {
    $conn = new PDO("pgsql:host=$host;dbname=$dbname", $user, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $stmt = $conn->prepare("SELECT resources_policy,schedule,cpu_utilization,iscsi_utilization,iscsi_write,iscsi_read,vm_max_disk_write,vm_max_disk_read,vm_limit_disk_write,vm_limit_disk_read,net_utilization,net_rx,net_tx,vm_net_rx,vm_net_tx FROM resources_policy");
    $stmt->execute();
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    echo json_encode($result);
  } 
  catch(PDOException $e) {
    echo "Error: " . $e->getMessage();
  }
  $conn = null;
}

function modPolicys() {
  require('require/dbconfig.php');
  $resources_policy = $_POST["resources_policy"];
  $schedule = $_POST["schedule"];
  $cpu_utilization = $_POST["cpu_utilization"];
  $iscsi_utilization = $_POST["iscsi_utilization"];
  $iscsi_write = $_POST["iscsi_write"];
  $iscsi_read = $_POST["iscsi_read"];
  $vm_max_disk_write = $_POST["vm_max_disk_write"];
  $vm_max_disk_read = $_POST["vm_max_disk_read"];
  $vm_limit_disk_write = $_POST["vm_limit_disk_write"];
  $vm_limit_disk_read = $_POST["vm_limit_disk_read"];
  $net_utilization = $_POST["net_utilization"];
  $net_rx = $_POST["net_rx"];
  $net_tx = $_POST["net_tx"];
  $vm_net_rx = $_POST["vm_net_rx"];
  $vm_net_tx = $_POST["vm_net_tx"];
  try {
    $conn = new PDO("pgsql:host=$host;dbname=$dbname", $user, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    if ($resources_policy == 0) { 
      shell_exec("/usr/bin/sudo ../resources-control-script/start_stop.sh stop");
      $stmt = $conn->prepare("UPDATE resources_policy SET resources_policy=$resources_policy");
    } else {
      shell_exec("/usr/bin/sudo ../resources-control-script/start_stop.sh start $schedule");
      $stmt = $conn->prepare("UPDATE resources_policy SET resources_policy=$resources_policy, schedule=$schedule, cpu_utilization=$cpu_utilization, iscsi_utilization=$iscsi_utilization, iscsi_write=$iscsi_write, iscsi_read=$iscsi_read,vm_max_disk_write=$vm_max_disk_write ,vm_max_disk_read=$vm_max_disk_read , vm_limit_disk_write=$vm_limit_disk_write, vm_limit_disk_read=$vm_limit_disk_read, net_utilization=$net_utilization, net_rx=$net_rx, net_tx=$net_tx, vm_net_rx=$vm_net_rx, vm_net_tx=$vm_net_tx");
    }
    $stmt->execute();
    echo "Policy update successfully!";
  }
  catch(PDOException $e) {
    echo $sql . "<br>" . $e->getMessage();
  }
  $conn = null;
}

function startVM() {
  $vm_id = $_POST["id"];
  if (!empty($vm_id)){
    chdir('../resources-control-script');
    foreach ($vm_id as $id) {
      exec("/usr/bin/sudo ./vm_start_load_balancing.sh $id");
    }
    echo "ok";
  }
}

if (function_exists($_GET['f'])) {
  $_GET['f']();
}
?>
