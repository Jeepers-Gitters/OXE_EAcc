# OXE_EAcc
 Alcatel-Lucent OmniPCX Enterprise PABX Ethernet Real-Time accounting tickets Processor script written in PowerShell
# Notes
* Written in PowerShell as main purpose was just to save tickets. For processing of the files you need another tools.
* No DNS support, only IP-address of CPU supported
* No support of spatial redundancy at the moment
* Writes CDR, MAO and VoIP tickets in files. No processing of VoIP files at the moment
* Tested only on Windows
# Installation
 Copy .ps1 and eacc.ini files to any folder you like, change parameters in eacc.ini file
# Configuraition
 Script parameters are configured in eacc.ini file. Names are self-explanatory nevertheless here is description:
 - CPU: Main CPU address, only IPv4 addresses supported
 - Port: Default is 2533. May be needed in case of NATed connection to OXE (Never tried)
 - WorkingDir: The directory on your PC where you want to save tickets files and log. Should have write permissions.
 - Logging: If set to "1" writes log file of received messages
 - Debugging: If set to "1" enables debugging messages on console
 - CDRPrint: If set to "1" prints CDR one-liner on console
 - CDRBeep: If set to "1" beeps on every ticket received (could be annoying)
 Changed parameters are taken into account after restart of script
 Sending of CDR, MAO and VoIP tickets from CPU also needs certain configuration on PABX side - see System Documentation
# Run
 Set execution Policy for Powershell scripts on your PC or server so that you can run this script (See e.g. <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.4>)
# To-Do
* Spatial Redundancy support
* Script signing for security
* Windows Service mode (for automatic restart etc)
* Test on Linux
 
