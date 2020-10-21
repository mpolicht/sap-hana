variable "resource-group" {
  description = "Details of the resource group"
}

variable "vnet-sap" {
  description = "Details of the SAP VNet"
}

variable "storage-bootdiag" {
  description = "Details of the boot diagnostics storage account"
}

variable "ppg" {
  description = "Details of the proximity placement group"
}

variable naming {
  description = "Defines the names for the resources"
}

variable "custom_disk_sizes_filename" {
  type        = string
  description = "Disk size json file"
  default     = ""
}

variable "admin_subnet" {
  description = "Information about SAP admin subnet"
}

locals {
  // Imports database sizing information

  sizes = jsondecode(file(length(var.custom_disk_sizes_filename) > 0 ? var.custom_disk_sizes_filename : "${path.module}/../../../../../configs/anydb_sizes.json"))

  computer_names       = var.naming.virtualmachine_names.ANYDB_COMPUTERNAME
  virtualmachine_names = var.naming.virtualmachine_names.ANYDB_VMNAME

  storageaccount_names = var.naming.storageaccount_names.SDU
  resource_suffixes    = var.naming.resource_suffixes

  region  = try(var.infrastructure.region, "")
  sap_sid = upper(try(var.application.sid, ""))
  prefix  = try(var.infrastructure.resource_group.name, var.naming.prefix.SDU)
  rg_name = try(var.infrastructure.resource_group.name, format("%s%s", local.prefix, local.resource_suffixes.sdu-rg))

  // Zones
  zones            = try(local.anydb.zones, [])
  zonal_deployment = length(local.zones) > 0 ? true : false
  db_zone_count    = try(length(local.zones), 1)

  # SAP vnet
  var_infra       = try(var.infrastructure, {})
  var_vnet_sap    = try(local.var_infra.vnets.sap, {})
  vnet_sap_arm_id = try(local.var_vnet_sap.arm_id, "")
  vnet_sap_exists = length(local.vnet_sap_arm_id) > 0 ? true : false
  vnet_sap_name   = local.vnet_sap_exists ? try(split("/", local.vnet_sap_arm_id)[8], "") : try(local.var_vnet_sap.name, "")
  vnet_nr_parts   = length(split("-", local.vnet_sap_name))
  // Default naming of vnet has multiple parts. Taking the second-last part as the name 
  vnet_sap_name_prefix = try(substr(upper(local.vnet_sap_name), -5, 5), "") == "-VNET" ? split("-", local.vnet_sap_name)[(local.vnet_nr_parts - 2)] : local.vnet_sap_name

  // Admin subnet
  var_sub_admin    = try(var.infrastructure.vnets.sap.subnet_admin, {})
  sub_admin_arm_id = try(local.var_sub_admin.arm_id, "")
  sub_admin_exists = length(local.sub_admin_arm_id) > 0 ? true : false
  sub_admin_name   = local.sub_admin_exists ? try(split("/", local.sub_admin_arm_id)[10], "") : try(local.var_sub_admin.name, format("%s%s", local.prefix, local.resource_suffixes.admin-subnet))
  sub_admin_prefix = try(local.var_sub_admin.prefix, "")

  // Admin NSG
  var_sub_admin_nsg    = try(var.infrastructure.vnets.sap.subnet_admin.nsg, {})
  sub_admin_nsg_arm_id = try(local.var_sub_admin_nsg.arm_id, "")
  sub_admin_nsg_exists = length(local.sub_admin_nsg_arm_id) > 0 ? true : false
  sub_admin_nsg_name   = local.sub_admin_nsg_exists ? try(split("/", local.sub_admin_nsg_arm_id)[8], "") : try(local.var_sub_admin_nsg.name, format("%s%s", local.prefix, local.resource_suffixes.admin-subnet-nsg))

  // DB subnet
  var_sub_db    = try(var.infrastructure.vnets.sap.subnet_db, {})
  sub_db_arm_id = try(local.var_sub_db.arm_id, "")
  sub_db_exists = length(local.sub_db_arm_id) > 0 ? true : false
  sub_db_name   = local.sub_db_exists ? try(split("/", local.sub_db_arm_id)[10], "") : try(local.var_sub_db.name, format("%s%s", local.prefix, local.resource_suffixes.db-subnet))
  sub_db_prefix = try(local.var_sub_db.prefix, "")

  // DB NSG
  var_sub_db_nsg    = try(var.infrastructure.vnets.sap.subnet_db.nsg, {})
  sub_db_nsg_arm_id = try(local.var_sub_db_nsg.arm_id, "")
  sub_db_nsg_exists = length(local.sub_db_nsg_arm_id) > 0 ? true : false
  sub_db_nsg_name   = local.sub_db_nsg_exists ? try(split("/", local.sub_db_nsg_arm_id)[8], "") : try(local.var_sub_db_nsg.name, format("%s%s", local.prefix, local.resource_suffixes.db-subnet-nsg))

  // PPG Information
  ppgId = lookup(var.infrastructure, "ppg", false) != false ? (var.ppg[0].id) : null

  anydb          = try(local.anydb-databases[0], {})
  anydb_platform = try(local.anydb.platform, "NONE")
  anydb_version  = try(local.anydb.db_version, "")

  // Dual network cards
  anydb_dual_nics = try(local.anydb.dual_nics, false)

  // Filter the list of databases to only AnyDB platform entries
  // Supported databases: Oracle, DB2, SQLServer, ASE 
  anydb-databases = [
    for database in var.databases : database
    if contains(["ORACLE", "DB2", "SQLSERVER", "ASE"], upper(try(database.platform, "NONE")))
  ]

  // Enable deployment based on length of local.anydb-databases
  enable_deployment = (length(local.anydb-databases) > 0) ? true : false

  // If custom image is used, we do not overwrite os reference with default value
  anydb_custom_image = try(local.anydb.os.source_image_id, "") != "" ? true : false

  anydb_ostype = try(local.anydb.os.os_type, "Linux")
  anydb_oscode = upper(local.anydb_ostype) == "LINUX" ? "l" : "w"
  anydb_size   = try(local.anydb.size, "Demo")
  anydb_sku    = try(lookup(local.sizes, local.anydb_size).compute.vm_size, "Standard_E4s_v3")
  anydb_fs     = try(local.anydb.filesystem, "xfs")
  anydb_ha     = try(local.anydb.high_availability, false)
  db_sid       = lower(substr(local.anydb_platform, 0, 3))
  loadbalancer = try(local.anydb.loadbalancer, {})

  node_count      = try(length(var.databases[0].dbnodes), 1)
  db_server_count = local.anydb_ha ? local.node_count * 2 : local.node_count

  authentication = try(local.anydb.authentication,
    {
      "type"     = upper(local.anydb_ostype) == "LINUX" ? "key" : "password"
      "username" = "azureadm"
  })

  anydb_cred           = try(local.anydb.credentials, {})
  db_systemdb_password = try(local.anydb_cred.db_systemdb_password, "")

  // Default values in case not provided
  os_defaults = {
    ORACLE = {
      "publisher" = "Oracle",
      "offer"     = "Oracle-Linux",
      "sku"       = "77",
      "version"   = "latest"
    }
    DB2 = {
      "publisher" = "suse",
      "offer"     = "sles-sap-12-sp5",
      "sku"       = "gen1"
      "version"   = "latest"
    }
    ASE = {
      "publisher" = "suse",
      "offer"     = "sles-sap-12-sp5",
      "sku"       = "gen1"
      "version"   = "latest"
    }
    SQLSERVER = {
      "publisher" = "MicrosoftSqlServer",
      "offer"     = "SQL2017-WS2016",
      "sku"       = "standard-gen2",
      "version"   = "latest"
    }
    NONE = {
      "publisher" = "",
      "offer"     = "",
      "sku"       = "",
      "version"   = ""
    }
  }

  anydb_os = {
    "source_image_id" = local.anydb_custom_image ? local.anydb.os.source_image_id : ""
    "publisher"       = try(local.anydb.os.publisher, local.anydb_custom_image ? "" : local.os_defaults[upper(local.anydb_platform)].publisher)
    "offer"           = try(local.anydb.os.offer, local.anydb_custom_image ? "" : local.os_defaults[upper(local.anydb_platform)].offer)
    "sku"             = try(local.anydb.os.sku, local.anydb_custom_image ? "" : local.os_defaults[upper(local.anydb_platform)].sku)
    "version"         = try(local.anydb.os.version, local.anydb_custom_image ? "" : local.os_defaults[upper(local.anydb_platform)].version)
  }

  // Update database information with defaults
  anydb_database = merge(local.anydb,
    { platform = local.anydb_platform },
    { db_version = local.anydb_version },
    { size = local.anydb_size },
    { os = merge({ os_type = local.anydb_ostype }, local.anydb_os) },
    { filesystem = local.anydb_fs },
    { high_availability = local.anydb_ha },
    { authentication = local.authentication },
    { credentials = {
      db_systemdb_password = local.db_systemdb_password
      }
    },
    { dbnodes = local.dbnodes },
    { loadbalancer = local.loadbalancer }
  )

  dbnodes = flatten([[for idx, dbnode in try(local.anydb.dbnodes, [{}]) : {
    name         = try("${dbnode.name}-0", format("%s_%s%s", local.prefix, local.virtualmachine_names[idx], local.resource_suffixes.vm))
    computername = try("${dbnode.name}-0", local.computer_names[idx], local.resource_suffixes.vm)
    role         = try(dbnode.role, "worker"),
    db_nic_ip    = lookup(dbnode, "db_nic_ips", [false, false])[0]
    admin_nic_ip    = lookup(dbnode, "admin_nic_ips", [false, false])[0]
    }
    ],
    [for idx, dbnode in try(local.anydb.dbnodes, [{}]) : {
      name         = try("${dbnode.name}-1", format("%s_%s%s", local.prefix, local.virtualmachine_names[idx + local.node_count], local.resource_suffixes.vm))
      computername = try("${dbnode.name}-1", local.computer_names[idx + local.node_count], local.resource_suffixes.vm)
      role         = try(dbnode.role, "worker"),
      db_nic_ip    = lookup(dbnode, "db_nic_ips", [false, false])[1],
      admin_nic_ip    = lookup(dbnode, "admin_nic_ips", [false, false])[1]
      } if local.anydb_ha
    ]
    ]
  )

  anydb_vms = [
    for idx, dbnode in local.dbnodes : {
      platform       = local.anydb_platform,
      name           = dbnode.name
      computername   = dbnode.computername
      db_nic_ip      = dbnode.db_nic_ip
      size           = local.anydb_sku
      os             = local.anydb_ostype,
      authentication = local.authentication
      sid            = local.sap_sid
    }
  ]

  // Ports used for specific DB Versions
  lb_ports = {
    "ASE" = [
      "1433"
    ]
    "ORACLE" = [
      "1521"
    ]
    "DB2" = [
      "62500"
    ]
    "SQLSERVER" = [
      "59999"
    ]
    "NONE" = [
      "80"
    ]
  }

  loadbalancer_ports = flatten([
    for port in local.lb_ports[upper(local.anydb_platform)] : {
      port = tonumber(port)
    }
  ])

  data-disk-per-dbnode = (length(local.anydb_vms) > 0) ? flatten(
    [
      for storage_type in lookup(local.sizes, local.anydb_size).storage : [
        for disk_count in range(storage_type.count) : {
          suffix               = format("%s%02d", storage_type.name, disk_count)
          storage_account_type = storage_type.disk_type,
          disk_size_gb         = storage_type.size_gb,
          //The following two lines are for Ultradisks only
          disk_iops_read_write      = try(storage_type.disk-iops-read-write, null)
          disk_mbps_read_write      = try(storage_type.disk-mbps-read-write, null)
          caching                   = storage_type.caching,
          write_accelerator_enabled = storage_type.write_accelerator
        }
      ]
      if storage_type.name != "os"
    ]
  ) : []

  anydb_disks = flatten([
    for vm_counter, anydb_vm in local.anydb_vms : [
      for idx, datadisk in local.data-disk-per-dbnode : {
        name                      = format("%s-%s", anydb_vm.name, datadisk.suffix)
        vm_index                  = vm_counter
        caching                   = datadisk.caching
        storage_account_type      = datadisk.storage_account_type
        disk_size_gb              = datadisk.disk_size_gb
        write_accelerator_enabled = datadisk.write_accelerator_enabled
        disk_iops_read_write      = datadisk.disk_iops_read_write
        disk_mbps_read_write      = datadisk.disk_mbps_read_write
        lun                       = idx
      }
    ]
  ])

  storage_list = lookup(local.sizes, local.anydb_size).storage
  enable_ultradisk = try(compact([
    for storage in local.storage_list :
    storage.disk_type == "UltraSSD_LRS" ? true : ""
  ])[0], false)

}
