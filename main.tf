terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.97.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "shd-rg" {
  name     = "shd-resources"
  location = "East Us"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "shd-vn" {
  name                = "shd-network"
  resource_group_name = azurerm_resource_group.shd-rg.name
  location            = azurerm_resource_group.shd-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "shd-subnet" {
  name                 = "shd-subnet"
  resource_group_name  = azurerm_resource_group.shd-rg.name
  virtual_network_name = azurerm_virtual_network.shd-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "shd-sg" {
  name                = "shd-sg"
  location            = azurerm_resource_group.shd-rg.location
  resource_group_name = azurerm_resource_group.shd-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "shd-dev-rule" {
  name                        = "shd-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.shd-rg.name
  network_security_group_name = azurerm_network_security_group.shd-sg.name
}

resource "azurerm_subnet_network_security_group_association" "shd-sga" {
  subnet_id                 = azurerm_subnet.shd-subnet.id
  network_security_group_id = azurerm_network_security_group.shd-sg.id
}

resource "azurerm_public_ip" "shd-ip" {
  name                = "shd-ip"
  resource_group_name = azurerm_resource_group.shd-rg.name
  location            = azurerm_resource_group.shd-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "shd-nic" {
  name                = "shd-nic"
  location            = azurerm_resource_group.shd-rg.location
  resource_group_name = azurerm_resource_group.shd-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.shd-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.shd-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "shd-vm" {
  name                  = "shd-vm"
  resource_group_name   = azurerm_resource_group.shd-rg.name
  location              = azurerm_resource_group.shd-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.shd-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/shdazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
      command = templatefile("${var.host_os}-ssh-script.tpl", {
          hostname = self.public_ip_address,
          user = "adminuser",
          identityfile = "~/.ssh/shdazurekey"
      })
      interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "shd-ip-data" {
    name = azurerm_public_ip.shd-ip.name
    resource_group_name = azurerm_resource_group.shd-rg.name
}

output "public_ip_address" {
    value = "${azurerm_linux_virtual_machine.shd-vm.name}: ${data.azurerm_public_ip.shd-ip-data.ip_address}"
}