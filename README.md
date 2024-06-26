[![Hits](https://hits.sh/github.com/Jeepers-Gitters/OXE_EAcc.svg)](https://hits.sh/github.com/Jeepers-Gitters/OXE_EAcc/)
[![Github All Releases](https://img.shields.io/github/downloads/Jeepers-Gitters/OXE_EAcc/total.svg)]()
# OXE_EAcc
 Alcatel-Lucent OmniPCX Enterprise PABX Ethernet Real-Time accounting tickets Processor script written in PowerShell
* Written in PowerShell as main purpose is just to save tickets for further processing. For that processing of the files you need another tools.
* No DNS support, only IP-address of CPU supported
* Stores received CDR, MAO and VoIP tickets in plain text files. Just storing files - No processing of VoIP files at the moment
* Tested on Powershell 5 and Powershell 7.1
* Tested  on Windows OS's and Ubuntu 22
# Installation
## Windows 
 Copy _tabs24.ps1_ and _eacc.ini_ files to any folder you like, change parameters in _eacc.ini_ file
## Linux
 Install _pwsh_ - see <https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.4>
 Copy _tabs24.ps1_ and _eacc.ini_ files to any folder you like, change parameters in _eacc.ini_ file
# Configuration
 Script parameters are configured in eacc.ini file. Names are self-explanatory nevertheless here is the description:
 - CPU1: Main CPU address, only IPv4 addresses supported
 - CPU2: Main CPU 2 in case spatial redundancy is used, leave blank if no spatial redundancy
 - Port: Default is 2533. May be needed in case of NATed connection to OXE (Never tried)
 - WorkingDir: The directory on your PC where you want to save tickets files and log. Should have write permissions. As this script runs in PowerShell in Linux there is no need to take care of directory separator ("\\" or "/")
 - Logging: If set to "1" writes log file of received messages. Log file gets overwritten every time this script is run
 - Debugging: If set to "1" enables debugging messages on console
 - CDRPrint: If set to "1" prints CDR one-liner on console for monitoring purpose
 - CDRBeep: If set to "1" beeps on every ticket received (could be annoying)
 - Changed parameters are taken into account after restart of script
 - Sending of CDR, MAO and VoIP tickets from CPU also needs certain configuration on PABX side - see OXE's System Documentation 
# Run
## Windows 
 * Start Powershell console (not recommended to run it in Windows Powershell ISE or Visual Studio Code)
 * Set execution Policy for Powershell scripts on your PC or server so that you can run this script (See e.g. <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.4>)
 * Run script _.\tabs24.ps1_
## Linux
 * run _"pwsh"_ then run _".\tabs24.ps1"_ or just run _"pwsh .\tabs24.ps1"_ from Linux CLI
# Additional information
 * CDRs are stored in files with "MainCPUAddress" as name and with .cdr .mao .voip as extensions. They gets appended on every start of the script.
 * Screen example:
![изображение](https://github.com/Jeepers-Gitters/OXE_EAcc/blob/01edf063fa7f6bb095ea26283e51f405a9fd0146/163.jpg)
 * Printed CDR fields. Check [call_types.txt](https://github.com/Jeepers-Gitters/OXE_EAcc/blob/main/call_types.txt) for full description.
    - "ChargedNumber"
    - "CalledNumber"
    - "CallType"
    - "StartDate"
    - "StartTime"
    - "Duration"
    - "Waiting Duration"
    - "TrunkGroupNumber"
    - "InitialDialledNumber"
# Notes
 * I noticed that in single CPU configuration sending of tickets starts after a couple of minutes after proper connection initialization. Just wait for tickets to appear.. In twin CPU configuration there is no such problem.
 * Only one client can receive tickets on Ethernet so this script uses .lock file ($EALockFile) for check whether it's already running.
 * After Ctrl-C was pressed it takes some time to return to command prompt - up to 30 seconds.
 * For questions you could use "Discussion" button here and create a topic or use already existing one.
# To-Do
 * ~~Ctrl-C processing inside the script for clean break~~ Done
 * ~~Spatial Redundancy and switchover support~~ Done
 * Script signing for security
 * Windows Service mode (for automatic restart etc)
 *  ~~Test on Linux~~ Done
 *  Separate files for each day, folders for months
# Disclaimer
 This script is distributed "AS IS". Use it at your own risk. No immediate bug correction. no additional feature implementation guaranteed.
 
