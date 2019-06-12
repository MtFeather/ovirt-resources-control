$(document).ready(function(){
  $("#policyBtn").click(function(){
    getPolicys();
  });
  $('#resourcesControl').change(function(){
    if ($('#resourcesControl').is(':checked') == true){
      $('.resources-policy label').addClass('labelEnabled');
      $('.resources-policy label').removeClass('labelDisabled');
      $('.resources-policy input').prop('disabled', false);
    } else {
      $('.resources-policy label').addClass('labelDisabled');
      $('.resources-policy label').removeClass('labelEnabled');
      $('.resources-policy input').prop('disabled', true);
    }
  });
  $("#policysForm").submit(function(event) {
    event.preventDefault();
    if (validatePolicysForm() != 'false') {
      modPolicys();
    }
  });
  $.fn.dataTable.ext.classes.sPageButton = 'btn btn-default GKGFBNLBANB';
});
var VM_LIMIT_PLUGIN_MESSAGE_PREFIX = 'vm-limit-plugin';
var VM_LIMIT_PLUGIN_MESSAGE_DELIM = ':';

function getVmList(vms, vm_names) {
  vm_names = vm_names.map(x => "'" + x + "'").toString();
  var vms_Table = $("#vms_table").DataTable({
    "ajax": {
      url: "function.php?f=getVmList",
      type: "POST",
      data: { "vms": vms, "vm_names": vm_names }
    },
    "columns": [
       { 
         "data": "name",
         "render": function ( data, type, row, meta ) {
           return '<a href="/ovirt-engine/webadmin/?#vms-general;name='+data+'" target="_parent">'+data+'</a>';
         }
       },
       {
         "data": "host",
         "render": function ( data, type, row, meta ) {
           return '<a href="/ovirt-engine/webadmin/?#hosts-general;name='+data+'" target="_parent">'+data+'</a>';
         }
       },
       { "data": "cpu" },
       { "data": "disk_read" },
       { "data": "disk_write" },
       { "data": "net_rx" },
       { "data": "net_tx" }
    ],
    "dom": "<'content-view-pf-pagination clearfix'"+
           "<'form-group'B>"+
           "<'form-group'<i><'btn-group btn-pagination'p>>>t",
    "pagingType": "simple",
    "pageLength": 100,
    "language": {
      "zeroRecords": "No matching records found",
      "info": "_START_ - _END_",
      "paginate": {
        "previous": '<i class="fa fa-angle-left"></i>',
        "next": '<i class="fa fa-angle-right"></i>'
      }
    },
    buttons: [
      {
        "text": '<i class="fa fa-refresh"></i>',
        "className": 'btn btn-default',
        "action": function ( e, dt, node, config ) {
          parent.postMessage(VM_LIMIT_PLUGIN_MESSAGE_PREFIX + VM_LIMIT_PLUGIN_MESSAGE_DELIM + 'getVmList', "*");
          dt.ajax.reload();
        }
      }
    ]
  });
  $('#SearchPanelView_searchStringInput').keyup(function(){
    vms_Table.search($(this).val()).draw();
  });
  $('#SearchPanelView_searchClean').click(function(){
    $('#SearchPanelView_searchStringInput').val('');
    vms_Table.search('').draw();
  });
};    

function getPolicys() {
  $.ajax({
    url: "function.php?f=getPolicys",
    success: function(result){
      if (!result) {
        alert("Get Policy Error!");
      } else {
        var row = JSON.parse(result);
        if (row["resources_policy"] == 0) {
          $('#resourcesControl').prop("checked", false);
          $('.resources-policy label').addClass('labelDisabled');
          $('.resources-policy label').removeClass('labelEnabled');
          $('.resources-policy input').prop('disabled', true);
        } else {
          $('#resourcesControl').prop("checked", true);
          $('.resources-policy label').addClass('labelEnabled');
          $('.resources-policy label').removeClass('labelDisabled');
          $('.resources-policy input').prop('disabled', false);
        }
        $("#schedule").val(row["schedule"]);
        $("#cpuUtilization").val(row["cpu_utilization"]);
        $("#iscsiUtilization").val(row["iscsi_utilization"]);
        $("#iscsiWrite").val(row["iscsi_write"]);
        $("#iscsiRead").val(row["iscsi_read"]);
        $("#vmMaxDiskWrite").val(row["vm_max_disk_write"]);
        $("#vmMaxDiskRead").val(row["vm_max_disk_read"]);
        $("#vmLimitDiskWrite").val(row["vm_limit_disk_write"]);
        $("#vmLimitDiskRead").val(row["vm_limit_disk_read"]);
        $("#netUtilization").val(row["net_utilization"]);
        $("#netRX").val(row["net_rx"]);
        $("#netTX").val(row["net_tx"]);
        $("#vmNetRX").val(row["vm_net_rx"]);
        $("#vmNetTX").val(row["vm_net_tx"]);
      }
    }
  });
}

function validatePolicysForm() {
  var e = '';
  var formFields = [$('#schedule'), $('#cpuUtilization'), $('#iscsiUtilization'), $('#iscsiWrite'), $('#iscsiRead'), $('#vmMaxDiskWrite'), $('#vmMaxDiskRead'), $('#vmLimitDiskWrite'), $('#vmLimitDiskRead'), $('#netUtilization'), $('#netRX'), $('#netTX'), $('#vmNetRX'), $('#vmNetTX')];
  for (var i=0;i<formFields.length;i++) {
    if (formFields[i].val() == '' || isNaN(formFields[i].val())) {
      e = 'false';
      formFields[i].parents('.form-group').addClass('has-error');
    } else {
      //formFields[i].removeclass('has-error');
      formFields[i].parents('.form-group').removeClass('has-error');
    }
  }
  return e;
}

function modPolicys() {
  $.ajax({
    url: "function.php?f=modPolicys",
    method: "POST",
    data: {
      resources_policy: +$("#resourcesControl").is(":checked"),
      schedule: $("#schedule").val(),
      cpu_utilization: $("#cpuUtilization").val(),
      iscsi_utilization: $("#iscsiUtilization").val(),
      iscsi_write: $("#iscsiWrite").val(),
      iscsi_read: $("#iscsiRead").val(),
      vm_max_disk_write: $("#vmMaxDiskWrite").val(),
      vm_max_disk_read: $("#vmMaxDiskRead").val(),
      vm_limit_disk_write: $("#vmLimitDiskWrite").val(),
      vm_limit_disk_read: $("#vmLimitDiskRead").val(),
      net_utilization: $("#netUtilization").val(),
      net_rx: $("#netRX").val(),
      net_tx: $("#netTX").val(),
      vm_net_rx: $("#vmNetRX").val(),
      vm_net_tx: $("#vmNetTX").val()
    },
    success: function(result){
      if (result) {
        alert(result);
        $('#policysModal').modal('hide');
      }
    }
  });
}

parent.postMessage(VM_LIMIT_PLUGIN_MESSAGE_PREFIX + VM_LIMIT_PLUGIN_MESSAGE_DELIM + 'getVmList', "*");

