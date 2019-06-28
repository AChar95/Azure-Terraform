variable "prefix" {
  default = "vmACex"
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-resources"
  location = "uksouth"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "jenkins" {
  name                = "myPublicIP1"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method   = "Dynamic"
  domain_name_label   = "allan1-${formatdate("DDMMYYhhmmss", timestamp())}"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_public_ip" "wildfly" {
  name                = "myPublicIP2"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  allocation_method   = "Dynamic"
  domain_name_label   = "allan2-${formatdate("DDMMYYhhmmss", timestamp())}"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "myNetworkSecurityGroup"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  security_rule {
    name                       = "SSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "staging"
  }
}

resource "azurerm_network_interface" "jenkins" {
  name                      = "${var.prefix}-nic-1"
  location                  = "${azurerm_resource_group.main.location}"
  resource_group_name       = "${azurerm_resource_group.main.name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"


  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = "${azurerm_subnet.internal.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.jenkins.id}"
  }
  depends_on = [azurerm_network_security_group.main, azurerm_subnet.internal, azurerm_public_ip.jenkins]
}
resource "azurerm_network_interface" "wildfly" {
  name                      = "${var.prefix}-nic-2"
  location                  = "${azurerm_resource_group.main.location}"
  resource_group_name       = "${azurerm_resource_group.main.name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"


  ip_configuration {
    name                          = "testconfiguration2"
    subnet_id                     = "${azurerm_subnet.internal.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.wildfly.id}"
  }
  depends_on = [azurerm_network_security_group.main, azurerm_subnet.internal, azurerm_public_ip.wildfly]
}

resource "azurerm_virtual_machine" "jenkins" {
  name                  = "${var.prefix}-vmJK"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.jenkins.id}"]
  vm_size               = "Standard_DS1_v2"


  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "jenkinsVM"
    admin_username = "jenkins"
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/jenkins/.ssh/authorized_keys"
      key_data = "${file("/home/al/.ssh/id_rsa.pub")}"
    }
  }
  tags = {
    environment = "staging"
  }
  provisioner "remote-exec" {
    inline = ["sudo apt update", "sudo apt install -y jq", "sudo apt install git", "git clone https://github.com/AChar95/JenkinsScript.git", "cd JenkinsScript/scripts", "chmod 777 install.sh", "./install.sh"]
    connection {
      type        = "ssh"
      user        = "jenkins"
      private_key = "${file("/home/al/.ssh/id_rsa")}"
      host        = "${azurerm_public_ip.jenkins.fqdn}"
    }
  }
}

resource "azurerm_virtual_machine" "wildfly" {
  name                  = "${var.prefix}-vmWF"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.wildfly.id}"]
  vm_size               = "Standard_DS1_v2"


  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk2"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "wildflyVM"
    admin_username = "wildfly"
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/wildfly/.ssh/authorized_keys"
      key_data = "${file("/home/al/.ssh/id_rsa.pub")}"
    }
  }
  tags = {
    environment = "staging"
  }
  provisioner "remote-exec" {
    inline = ["sudo apt update", "sudo apt install -y jq", "sudo apt install git", "git clone https://github.com/AChar95/WildflyScript.git", "cd WildflyScript/scripts", "chmod 777 installWF.sh", "./installWF.sh"]
    connection {
      type        = "ssh"
      user        = "wildfly"
      private_key = "${file("/home/al/.ssh/id_rsa")}"
      host        = "${azurerm_public_ip.wildfly.fqdn}"
    }
  }
}
