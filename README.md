# OXE_EAcc
 Alcatel-Lucent OmniPCX Enterprise Ethernet Real-Time accounting tickets Processor script written in PowerShell
# Notes
* Written in PowerShell
* No DNS support, only IP-addresses
* No supoort of spatial redundancy at the moment
# Installation
 Copy .ps1 and eacc.ini files to any folder you like
# Configuraition
 Script parameters are configured in eacc.ini file. Names are self-explanatory nevertheless here is description:
 - CPU: Main CPU address, IPv4 address supported
 - Port: Default is 2533. May be needed in case of NATed connection to OXE (Never tried)
 - WorkingDir: The directory on your PC where you want to save tickets files and log. Should have write permissions.
 - Logging: If set to "1" writes log file of received messages
 - Debugging: If set to "1" enables debugging messages on console
 - CDRPrint: If set to "1" prints CDR one-liner on console
 - CDRBeep: If set to "1" beeps on every ticket received (could be annoying)
 Changed parameters are taken into account after restart of script
# To-Do
* Spatial Redundancy support
* 
 
