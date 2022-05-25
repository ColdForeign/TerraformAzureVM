// Provider settings //

terraform {
 required_providers {
   azurerm = {
       source = "hashicorp/azurerm"
       version = "~> 3.0.2"
   }
 } 

 required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
    subscription_id = "2efd4ade-411d-4dbe-bc87-b13ed3556bf4"
}

// Resource group //

resource "azurerm_resource_group" "nuwm-cloud" {
  name = "nuwm-cloud"
  location = "Australia East"
}

// Creating VNet, subnets (AzureCosmosDB endpoint) and public IP //

resource "azurerm_virtual_network" "nuwm-cloud" {
  name = "nuwm-network"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  address_space = [ "10.0.0.0/16" ]
}

resource "azurerm_subnet" "vm-subnet" {
  name = "vm-subnet"
  address_prefixes = [ "10.0.1.0/24" ]
  virtual_network_name = azurerm_virtual_network.nuwm-cloud.name
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  
  service_endpoints = [ "Microsoft.AzureCosmosDB" ]

  depends_on = [
    azurerm_virtual_network.nuwm-cloud
  ]
}

resource "azurerm_public_ip" "vm-public" {
  name = "vm-public"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  location = azurerm_resource_group.nuwm-cloud.location
  allocation_method = "Static"
  sku = "Standard"
}

resource "azurerm_public_ip" "lb-public" {
  name = "lb-public"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  location = azurerm_resource_group.nuwm-cloud.location
  allocation_method = "Static"
  sku = "Standard"
}

// Description of the security group and its rules //

resource "azurerm_network_security_group" "nuwm-cloud-security-public" {
  name = "nuwm-security-group-public"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
}

resource "azurerm_network_security_rule" "allow-ping" {
  name = "allow-ping"
  priority = 100
  direction = "Inbound"
  access = "Allow"
  protocol = "Icmp"
  source_port_range = "*"
  destination_port_range = "*"
  source_address_prefix = "*"
  destination_address_prefix = "*"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  network_security_group_name = azurerm_network_security_group.nuwm-cloud-security-public.name
}

resource "azurerm_network_security_rule" "allow-ssh" {
  name = "allow-ssh"
  priority = 110
  direction = "Inbound"
  access = "Allow"
  protocol = "Tcp"
  source_port_range = "*"
  destination_port_range = "22"
  source_address_prefix = "*"
  destination_address_prefix = "*"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  network_security_group_name = azurerm_network_security_group.nuwm-cloud-security-public.name
}

// Description of network interface and virtual machine // 

resource "azurerm_network_interface" "vm-net-interface-pub" {
  name = "vm-net-interface-pub"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name

  ip_configuration {
    name = "public"
    private_ip_address_allocation = "Dynamic"
    subnet_id = azurerm_subnet.vm-subnet.id
    public_ip_address_id = azurerm_public_ip.vm-public.id
  }
}

resource "azurerm_network_interface_security_group_association" "security-pub" {
  network_interface_id = azurerm_network_interface.vm-net-interface-pub.id
  network_security_group_id = azurerm_network_security_group.nuwm-cloud-security-public.id
}

resource "azurerm_linux_virtual_machine" "management" {
  name = "management"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  location = azurerm_resource_group.nuwm-cloud.location
  size = "Standard_B1s"
  admin_username = "coldforeign"
  admin_password = "Pa$$word!1"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.vm-net-interface-pub.id
  ]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "0001-com-ubuntu-server-focal"
    sku = "20_04-lts-gen2"
    version = "latest"
  }
}

// Description of interfaces and Security Group //

resource "azurerm_network_interface" "sensor-net-interface" {
  count = var.sensorsCount
  name = "vm-net-interface-sensor-${count.index}"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name

  ip_configuration {
    name = "internal"
    subnet_id = azurerm_subnet.vm-subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  enable_ip_forwarding = false
}

resource "azurerm_network_interface" "saver-net-interface" {
  count = var.saversCount
  name = "vm-net-interface-saver-${count.index}"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name

  ip_configuration {
    name = "internal"
    subnet_id = azurerm_subnet.vm-subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  enable_ip_forwarding = false
}

resource "azurerm_network_security_group" "nuwm-cloud-security-savers" {
  name = "nuwm-security-group-http"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
}

// Security Group rule and binding interfaces to Security Group //

resource "azurerm_network_security_rule" "allow-http" {
  name = "allow-http"
  priority = 100
  direction = "Inbound"
  access = "Allow"
  protocol = "Tcp"
  source_port_range = "*"
  destination_port_range = "80"
  source_address_prefix = "*"
  destination_address_prefix = "*"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  network_security_group_name = azurerm_network_security_group.nuwm-cloud-security-savers.name
}

resource "azurerm_network_interface_security_group_association" "savers-security-private" {
  count = var.saversCount
  network_interface_id = element(azurerm_network_interface.saver-net-interface.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.nuwm-cloud-security-savers.id
}

// VM for the application which will store data //

resource "azurerm_linux_virtual_machine" "savers" {
  count = var.saversCount
  name = "saver-${count.index}"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  location = azurerm_resource_group.nuwm-cloud.location
  size = "Standard_B1s"
  admin_username = "coldforeign"
  admin_password = "Pa$$word!1"
  disable_password_authentication = false
  network_interface_ids = [
    element(azurerm_network_interface.saver-net-interface.*.id, count.index)
  ]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "0001-com-ubuntu-server-focal"
    sku = "20_04-lts-gen2"
    version = "latest"
  }
}

// VM for the application that will generate data //

resource "azurerm_linux_virtual_machine" "sensor" {
  count = var.sensorsCount
  name = "sensor-${count.index}"
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  location = azurerm_resource_group.nuwm-cloud.location
  size = "Standard_B1s"
  admin_username = "coldforeign"
  admin_password = "Pa$$word!1"
  disable_password_authentication = false
  network_interface_ids = [
    element(azurerm_network_interface.sensor-net-interface.*.id, count.index)
  ]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "0001-com-ubuntu-server-focal"
    sku = "20_04-lts-gen2"
    version = "latest"
  }
}

// Load balancer, http sample and pool settings //

resource "azurerm_lb" "web-app-lb" {
  name = "Web-app-LB"
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  sku = "Standard"

  frontend_ip_configuration {
    name = "primary"
    public_ip_address_id = azurerm_public_ip.lb-public.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [
    azurerm_linux_virtual_machine.savers
  ]
}

resource "azurerm_lb_probe" "http-probe" {
  loadbalancer_id = azurerm_lb.web-app-lb.id
  name = "http-running-probe"
  port = 80

  depends_on = [
    azurerm_linux_virtual_machine.savers,
    azurerm_lb.web-app-lb
  ]
}

resource "azurerm_lb_backend_address_pool" "backend_pool" {
  name = "LB-backend_address_pool"
  loadbalancer_id = azurerm_lb.web-app-lb.id
  
  depends_on = [
    azurerm_linux_virtual_machine.savers,
    azurerm_lb.web-app-lb
  ]
}

// Configure balancing rules and association pool //

resource "azurerm_lb_rule" "http-rule" {
  loadbalancer_id = azurerm_lb.web-app-lb.id
  name = "HTTP"
  protocol = "Tcp"
  frontend_port = 80
  backend_port = 80
  frontend_ip_configuration_name = azurerm_lb.web-app-lb.frontend_ip_configuration.0.name
  backend_address_pool_ids = [ 
    azurerm_lb_backend_address_pool.backend_pool.id 
  ]
  probe_id = azurerm_lb_probe.http-probe.id

  depends_on = [
    azurerm_linux_virtual_machine.savers,
    azurerm_lb.web-app-lb,
    azurerm_lb_backend_address_pool.backend_pool,
    azurerm_network_interface_backend_address_pool_association.savers,
    azurerm_lb_probe.http-probe
  ]
}

resource "azurerm_network_interface_backend_address_pool_association" "savers" {
  count = var.saversCount
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
  ip_configuration_name = element(azurerm_network_interface.saver-net-interface.*.ip_configuration.0.name, count.index)
  network_interface_id = element(azurerm_network_interface.saver-net-interface.*.id, count.index)

  depends_on = [
    azurerm_lb.web-app-lb,
    azurerm_lb_backend_address_pool.backend_pool
  ]
}

// Automatic ansible installation on VM

resource "azurerm_virtual_machine_extension" "install-ansible" {
  name = "install-ansible"
  virtual_machine_id = azurerm_linux_virtual_machine.management.id
  publisher = "Microsoft.Azure.Extensions"
  type = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
  {
    "commandToExecute": "sudo apt update && sudo apt install -y software-properties-common && sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible -y"
  }
  SETTINGS
}

// Ansible inventory generation

resource "local_file" "ansible_inventory" {
  content = templatefile("./templates/inventory.tmpl", {
    savers_ip_addresses = azurerm_network_interface.saver-net-interface.*.private_ip_address
    sensors_ip_addresses = azurerm_network_interface.sensor-net-interface.*.private_ip_address
  })

  filename = "../ansible/inventory"
}

// Database description

resource "azurerm_cosmosdb_account" "db" {
  name = var.db-name
  location = azurerm_resource_group.nuwm-cloud.location
  resource_group_name = azurerm_resource_group.nuwm-cloud.name
  offer_type = "Standard"
  kind = "GlobalDocumentDB"

  enable_automatic_failover = true
  is_virtual_network_filter_enabled = true

  capabilities {
    name = "EnableCassandra"
  }

  capabilities {
    name = "EnableServerless"
  }

  virtual_network_rule {
    id = azurerm_subnet.vm-subnet.id
  }

  consistency_policy {
    consistency_level = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix = 100000
  }

  geo_location {
    location = azurerm_resource_group.nuwm-cloud.location
    failover_priority = 0
  }
}

// Description of file generation and output of IP addresses //

resource "local_file" "sensor-env" {
  content = templatefile("./templates/sensor_env.tmpl", {
    server_ip = azurerm_public_ip.lb-public.ip_address
  })

  filename = "../ansible/files/.sensor_env"
}

resource "local_file" "saver-env" {
  content = templatefile("./templates/saver_env.tmpl", {
    endpoint = "${var.db-name}.cassandra.cosmos.azure.com"
    primary_key = azurerm_cosmosdb_account.db.primary_key
    user = var.db-name
    db_port = 10350
  })

  filename = "../ansible/files/.saver_env"
}

output "manager_ip" {
  value = azurerm_public_ip.vm-public.ip_address
}

output "loadbalancer_id" {
  value = azurerm_public_ip.lb-public.ip_address
}
