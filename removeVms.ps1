Get-Process vmconnect | Stop-Process
get-vm posh* | stop-vm -Force -Passthru | remove-vm -Force
remove-item "$((get-vmhost).VirtualMachinePath)\posh*" -Recurse