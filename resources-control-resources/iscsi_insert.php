<?php
require('require/dbconfig.php');
if( isset($_POST["write"]) && isset($_POST["read"]) ) {
  $write = $_POST["write"];
  $read = $_POST["read"];
  try {
    $conn = new PDO("pgsql:host=$host;dbname=$dbname", $user, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $sql="INSERT INTO iscsi_loading (read, write, up_time) VALUES ($read,$write,now())";
    $conn->exec($sql);
    echo "New record created successfully";
  } 
  catch(PDOException $e) {
    echo $sql . "<br>" . $e->getMessage();
  }
  $conn = null;
}
?>
