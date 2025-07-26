output "dc_public_ip" {
  value = azurerm_public_ip.dc_pip.ip_address
}

output "ex_public_ip" {
  value = azurerm_public_ip.ex_pip.ip_address
}
