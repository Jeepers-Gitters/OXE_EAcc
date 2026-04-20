[![Hits](https://hits.sh/github.com/Jeepers-Gitters/OXE_EAcc.svg)](https://hits.sh/github.com/Jeepers-Gitters/OXE_EAcc/)
[![Github All Releases](https://img.shields.io/github/downloads/Jeepers-Gitters/OXE_EAcc/total.svg)]()
# OXE_EAcc
* Real-Time accounting tickets Processor script for Alcatel-Lucent OmniPCX Enterprise PABX CDR on Ethernet
* Written in PowerShell as the main purpose was just to save CDR tickets for further processing. For that processing of the saved tickets  another tools is required.
* Only IPv4 addresses supported
* No DNS support at the moment, only IP-addresses of CPU supported
* This script stores CDR, MAO and VoIP tickets received as plain text files. Just storing files - no processing of VoIP files at the moment
* Tested on Powershell 5 and Powershell 7.1
* Tested  on Windows OS's and Ubuntu 22
# Installation
## Windows 
 Copy _tabs24.ps1_ and _eacc.ini_ files to any folder you like, change parameters in _eacc.ini_ file according to your environment
## Linux
 Install _pwsh_ - see <https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.4>
 Copy _tabs24.ps1_ and _eacc.ini_ files to any folder you like, change parameters in _eacc.ini_ file according to your environment
# Configuration
 Script working parameters are configured in eacc.ini file. Names of the parameters are self-explanatory nevertheless here is the description:
 - CPU1: Main CPU IP-address (single CPU configuration or duplication used with only __one Main CPU address__)
 - CPU2: Main CPU second IP-address in case __spatial redundancy__ is used (that means there are __two different__ Main CPU addresses), leave blank if no spatial redundancy used
 - Port: TCP port in PABX, default is 2533. May be needed in case of NATed connection to OXE (Never tried)
 - WorkingDir: The directory on your PC/server where you want to save ticket's files and logs. Should have write permissions. As this script runs in PowerShell in Linux there is no need to take care of directory separator ("\\" or "/")
 - Logging: If set to "1" writes log file of received messages. Log file gets overwritten every time this script is run
 - Debugging: If set to "1" enables debugging messages on console
 - CDRPrint: If set to "1" prints CDR one-liner on console for monitoring purpose
 - CDRBeep: If set to "1" beeps on every ticket received (could be annoying f large amount of tickets)
 - Parameters changes are taken into account after restart of script
 - Sending of CDR, MAO and VoIP tickets from CPU also needs certain configuration on PABX side - see OXE's System Documentation 
# Run
## Windows 
 * Start Powershell console (not recommended to run it in Windows Powershell ISE or Visual Studio Code)
 * Set execution Policy for Powershell scripts on your PC or server so that you can run this script (See e.g. <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.4>)
 * Run script _.\tabs24.ps1_ from Powershell CLI
## Linux
 * run _"pwsh"_ then run _".\tabs24.ps1"_ or just run _"pwsh .\tabs24.ps1"_ from Linux CLI
# Additional information
 * CDRs are stored in files with "MainCPUAddress" as its name and with .cdr .mao .voip as its extensions. They get appended on every start of the script.
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
 * After Ctrl-C was pressed it takes some time to return to command prompt - just wait up to 30 seconds.
 * For questions you could use "Discussion" button here and create a topic or use already existing one.
# To-Do
 * ~~Ctrl-C processing inside the script for clean break~~ Done
 * ~~Spatial Redundancy and switchover support~~ Done
 * Script signing for security
 * Windows Service mode (for automatic restart etc)
 *  ~~Test on Linux~~ Done
 *  If no connection to CPU ask for choice - Wait or Exit
 *  Separate files for each day, folders for months
# Disclaimer
 This script is distributed "AS IS". Use it at your own risk. No immediate bug correction. no additional feature implementation guaranteed.
 
