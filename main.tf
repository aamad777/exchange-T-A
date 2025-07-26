
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "exchange-lab-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-WinRM"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "dc_pip" {
  name                = "dc01-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_public_ip" "ex_pip" {
  name                = "ex01-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Basic"
}

resource "azurerm_network_interface" "dc_nic" {
  name                = "dc01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.4"
    public_ip_address_id          = azurerm_public_ip.dc_pip.id
  }
}

resource "azurerm_network_interface" "ex_nic" {
  name                = "ex01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.0.5"
    public_ip_address_id          = azurerm_public_ip.ex_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "dc_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.dc_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface_security_group_association" "ex_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.ex_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_windows_virtual_machine" "dc_vm" {
  name                = "DC01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_D8s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc_nic.id]

  os_disk {
    name                 = "dc01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_windows_virtual_machine" "ex_vm" {
  name                = "EX01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_D8s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.ex_nic.id]

  os_disk {
    name                 = "ex01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "dc_winrm" {
  name                 = "enable-winrm-dc01"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private; Enable-PSRemoting -Force; winrm quickconfig -q; winrm set winrm/config/service/Auth @{Basic='true'}; winrm set winrm/config/service @{AllowUnencrypted='true'}; Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP' -Enabled True; Restart-Service winrm\""


    }
SETTINGS
}

resource "azurerm_virtual_machine_extension" "ex_winrm" {
  name                 = "enable-winrm-ex01"
  virtual_machine_id   = azurerm_windows_virtual_machine.ex_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private; Enable-PSRemoting -Force; winrm quickconfig -q; winrm set winrm/config/service/Auth @{Basic='true'}; winrm set winrm/config/service @{AllowUnencrypted='true'}; Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP' -Enabled True; Restart-Service winrm\""
    }
SETTINGS
}
