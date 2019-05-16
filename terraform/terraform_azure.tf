# Configure the Microsoft Azure Provider
provider "azurerm" {
    subscription_id = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    client_id       = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    client_secret   = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    tenant_id       = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

# Create resource group if it doesn’t exist
resource "azurerm_resource_group" "awxgroup" {
    name     = "${azurerm_resource_group.tf_azure_guide.name}"
    location = "${var.location}"

    tags {
        environment = "Ansible AWX"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "awxnetwork" {
    name                = "ansible_awx"
    address_space       = ["${var.address_space}"]
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.myterraformgroup.name}"

    tags {
        environment = "Ansible AWX"
    }
}

# Create subnet
resource "azurerm_subnet" "awxsubnet" {
    name                 = "ansible_awx_Subnet"
    resource_group_name  = "${azurerm_resource_group.awxgroup.name}"
    virtual_network_name = "${azurerm_virtual_network.awxnetwork.name}"
    address_prefix       = "${var.subnet_prefix}"
}

# Create public IPs
resource "azurerm_public_ip" "awxpublicip" {
    name                         = "awxPublicIP"
    location                     = "${var.location}"
    resource_group_name          = "${azurerm_resource_group.awxgroup.name}"
    allocation_method            = "Dynamic"

    tags {
        environment = "Ansible AWX"
    }
}

# Security group to allow inbound access on port 80 (http) and 22 (ssh)
resource "azurerm_network_security_group" "awx-vm-sg" {
  name                = "${var.prefix}-sg"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.tf_azure_guide.name}"

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${var.source_network}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.source_network}"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "awxnic" {
    name                      = "awxNIC"
    location                  = "${var.location}"
    resource_group_name       = "${azurerm_resource_group.awxgroup.name}"
    network_security_group_id = "${azurerm_network_security_group.awxnsg.id}"

    ip_configuration {
        name                          = "awxNicConfiguration"
        subnet_id                     = "${azurerm_subnet.awxsubnet.id}"
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = "${azurerm_public_ip.awxpublicip.id}"
    }

    tags {
        environment = "Ansible AWX"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = "${azurerm_resource_group.awxgroup.name}"
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "awxstorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.awxgroup.name}"
    location                    = "${var.location}"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags {
        environment = "Ansible AWX"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "awxvm" {
    name                  = "${var.hostname}"
    location              = "${var.location}"
    resource_group_name   = "${azurerm_resource_group.awxgroup.name}"
    network_interface_ids = ["${azurerm_network_interface.awxnic.id}"]
    vm_size               = "${var.vm_size}"

    storage_os_disk {
    name              = "${var.hostname}-osdisk"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    }

    storage_image_reference {
   publisher = "${var.image_publisher}"
   offer     = "${var.image_offer}"
   sku       = "${var.image_sku}"
   version   = "${var.image_version}"
    }

    os_profile {
      computer_name  = "${var.hostname}"
      admin_username = "${var.admin_username}"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3Nz{snip}hwhqT9h"
        }
    }

  # run provisioners.
  provisioner "file" {
    source      = "scripts/install_common.sh"
    destination = "/home/${var.admin_username}/common.sh"
    # Install Ansible
    source      = "scripts/install_ansible_azure.sh"
    destination = "/home/${var.admin_username}/install_ansible_azure.sh"
    # Install Docker
    source      = "scripts/install_docker_ce.sh"
    destination = "/home/${var.admin_username}/install_docker_ce.sh"
    # Install Ansible awx
    source      = "scripts/install_ansible_awx.sh"
    destination = "/home/${var.admin_username}/install_ansible_awx.sh"
    # Configure Ansible
    source      = "scripts/configure_ansible_awx.sh"
    destination = "/home/${var.admin_username}/configure_ansible_awx.sh"

    # This shell script installs common attributes.
    provisioner "remote-exec" {
      inline = [
        "chmod +x /home/${var.admin_username}/common.sh",
        "sudo /home/${var.admin_username}/common.sh",
        "chmod +x /home/${var.admin_username}/install_ansible_azure.sh",
        "sudo /home/${var.admin_username}/install_ansible_azure.sh",
        "chmod +x /home/${var.admin_username}/install_docker_ce.sh",
        "sudo /home/${var.admin_username}/install_docker_ce.sh",
        "chmod +x /home/${var.admin_username}/install_ansible_awx.sh",
        "sudo /home/${var.admin_username}/install_ansible_awx.sh",
        "chmod +x /home/${var.admin_username}/configure_ansible_awx.sh",
        "sudo /home/${var.admin_username}/configure_ansible_awx.sh",
      ]

    connection {
      type     = "ssh"
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.tf-guide-pip.fqdn}"
    }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = "${azurerm_storage_account.awxstorageaccount.primary_blob_endpoint}"
    }

    tags {
        environment = "Ansible AWX"
    }
}
