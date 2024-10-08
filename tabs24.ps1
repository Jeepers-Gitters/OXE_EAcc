﻿
<#PSScriptInfo

.VERSION 0.9

.GUID d37ef3db-b18e-4d74-a3d4-10b2cc7d1787

.AUTHOR Jeepers-Gitters@github.com

.COMPANYNAME 

.COPYRIGHT 

.TAGS OXE ALU CDR SMDR 

.LICENSEURI 

.PROJECTURI https://github.com/Jeepers-Gitters/OXE_EAcc 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 
 
.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
 - modified for Linux pwsh compatibilities

.DESCRIPTION 
This script uses ALU netaccess protocol for receiving real-time tickets on Ethernet. All received tickets without
 any processing are written to appropriate files. 

#> 
#Requires -Version 5

Param(
  [Alias ("addr", "main")]
  [Parameter ( Position = 0, Mandatory = $false, HelpMessage = "Enter Main role CPU address here" )] $EAOXEMain = "192.168.92.52",
  
  [Alias ("port")]
  [Parameter (Position = 1, Mandatory = $false, HelpMessage = "Enter netaccess Port here")]
  $EATicketPort = 2533,
  
  [Alias ("log")]
  [Parameter (Mandatory = $false )]
  [Switch] $EALogEnable 
)

# Counter for main loop reenters (switchovers, e.g.)
$StartCounter = 0
# This data is generated from uncompressed TAX*.DAT file header. Could be extracted with this line from any file
# cp /usr4/account/TAXBAWKO.DAT . ; mv TAXBAWKO.DAT TAXBAWKO.Z |  compress -d -c TAXBAWKO.Z | head -n 1 |  tr -d "#" | awk '{ORS=NR%4?",":"\n"}1' RS=, | tr "," "\t" > header.dat
$TicketFields = @(4, 5, 30, 30, 20, 10, 16, 5, 20, 30, 2, 1, 17, 5, 10, 10, 5, 5, 5, 1, 16, 7, 1, 2, 10, 5, 40, 40, 10, 10, 10, 10, 1, 2, 2, 2, 30, 5, 10, 1, 17, 30, 5, 5, 5, 5, 5, 6, 6)
$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
# Application level ticket length
$TicketMessageLength = 772
# Abbreviations for call types
$EACallTypes = @("OC", "OCP", "PN", "LN", "IC", "ICP", "UN", "PO", "POP", "IP", "PIP", "11", "12", "PIC", "LL", "LT")
#
$TicketMark = "01-00"
$TestMark = "00-08"
$BufferTest = "00-08-54-45"
$EmptyTicket = "01-00-01-00"
$CDRTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$VoIPTicket = "01-00-07-00"
$TicketReadyMark = "03-04"
$EATestRequest = "TEST_REQ"
$EATestReply = "TEST_REP"
$StartMsg = "00-01"
$MainRole = "50"
$ThreeBytesAnswer = $StartMsg + "-" + $MainRole
$FiveBytesAnswer = $ThreeBytesAnswer + "-" + $TicketReadyMark
#
$TicketTruncated = $false
$TicketReady = $false
$Global:CDRCounter = 0
[int]$MAOCounter = 0
[int]$VOIPCounter = 0
$Global:TicketForm = @()
# Here we load all what is received from Ethernet
$BufferBuffer = @()
#
$StartPointer = 0
#
$EAIterationCounter = 0 
# Bytes left in buffer after an iteration
$EALeftToProcess = 0 
# Should ticket info be printed on console
$TicketPrintOut = $false
# Was Keep-Alive request received
$EAKeepAliveReq = $false
#
$SpatialConfiguration = $false
#
$CPUSwitchover = $true
[int]$EAMessageCounter = 0
# Get Linux and Windows compatibility directiry separator
$DirSeparator = [IO.Path]::DirectorySeparatorChar
# Messages to send
[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02, 0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x08
[Byte[]]$TestMessage = 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
$FullTestReply = $TestReply + $TestMessage
# Ini file
$EAInitFile = $PSScriptRoot + $DirSeparator + "eacc.ini"
$EALockFile = $PSScriptRoot + $DirSeparator + ".lock"

# Timer for TCP connection
# for checking
$TCPReceiveTimeoutCheck = 10000
# for established connection
$TCPReceiveTimeoutConnected = 31000
# Debug preferences
#$DebugPreference = "SilentlyContinue"
$DebugPreference = "Continue"
# Enable for debugging
$ErrorActionPreference = "SilentlyContinue"
#$ErrorActionPreference = "Stop"
# thanks to Oliver Lipkau for ini-file processing function
# https://devblogs.microsoft.com/scripting/use-powershell-to-work-with-any-ini-file/
# As output we receive hasharray of parameters defined in .ini file
function Get-IniContent ($IniFile) {
  $EAccini = @{}
  switch -regex -file $IniFile {
    “^\[(.+)\]” {
      # Section
      $section = $matches[1]
      $EAccini[$section] = @{}
      $CommentCount = 0
    }
    “^(;.*)$” {
      # Comment
      $value = $matches[1]
      $CommentCount = $CommentCount + 1
      $name = “Comment” + $CommentCount
      $EAccini[$section][$name] = $value
    }
    “(.+?)\s*=(.*)” {
      # Key
      $name, $value = $matches[1..2]
      $EAccini[$section][$name] = $value
    }
  }
  return $EAccini
} 

# Name is not complying with the naming rules for PowerShell. Correct later
function CheckOXE {
  Write-Host  -NoNewline "Host $EAOXECPU1 reachable : "
  if ( Test-Connection $EAOXECPU1 -Count 1 -Quiet   ) {
    Write-Host -ForegroundColor Green "OK"
    $EAOXEMain = $EAOXECPU1
    $EAOXEStby = $EAOXECPU2
    }
    else {
      Write-Host -ForegroundColor Red "NOK"
      if ( $NeedToCheckMainCPU ) {
        Write-Debug -Message "Checking 2nd CPU address"
        Write-Host  -NoNewline "Host $EAOXECPU2 reachable : "
          if ( Test-Connection $EAOXECPU2 -Count 1 -Quiet   ) {
            Write-Host -ForegroundColor Green "OK"
            $NeedToCheckMainCPU = $false
            $EAOXEMain = $EAOXECPU2
            $EAOXEStby = $EAOXECPU1
            }
            else {
              Write-Host -ForegroundColor Red "NOK"
              Write-Host "No connection to the host. Exiting."
              Clear-LockFile
              exit $EAErrorHost
              }
  }
  else {
#    Write-Host -ForegroundColor Red "NOK"
    Write-Host "No connection to the host. Exiting."
    Clear-LockFile
    exit $EAErrorHost
    }
}
Write-Host "Call-Server $EAOXEMain is Main"
# if ping is OK then check connection on port 2533 on Main CPU
  Write-Host -NoNewline "Connection on $EAOXEMain" port "$EATicketPort : "
  $Client = New-Object System.Net.Sockets.TCPClient($EAOXEMain, $EATicketPort)
  $Stream = $Client.GetStream() 
  $Client.ReceiveTimeout = $TCPReceiveTimeoutCheck

  if ( $Client.Connected ) {
    Write-Host -ForegroundColor Green "OK`n"
  }
  else {
    Write-Host -ForegroundColor Red "NOK"
    Write-Debug -Message "Exiting. Ethernet Account port closed on $($EAOXEMain)."
    Clear-LockFile
    exit $EAErrorPort
  } 
  $Client.Close()
  return $EAOXEMain, $EAOXEStby
}
# This function is used in case of exit so it's just could modified to Exit function with return code parameter. Correct later
function Clear-LockFile () {
  if ( ( Test-Path $EALockFile ) ) {
    Remove-Item -Path  $EALockFile -Force
  }
}

function ProcessOneTicket() {
  $Global:TicketForm = @(
    $TicketFields | Select-Object | ForEach-Object {
      $ProcessTicket.Remove($_)
      $ProcessTicket = $ProcessTicket.Substring($_)
    }
  )
  $Global:CDRCounter++
  "Ticket Proccessed $Global:CDRCounter, $MAOCounter, $VOIPCounter" | Out-File   -FilePath $EALogFile -Append
  # Display full ticket contents and trim spaces
  # Save one line in a file
  for ($f = 2; $f -lt $Global:TicketForm.Length; $f++) {
    $Global:TicketForm[$f] = $Global:TicketForm[$f].Trim()
  }
  if ( $TicketPrintOut ) {
    #
    # Full non-processed ticket printout (in case you need it) mainly used for debugging
    #    Write-Host "--- Ticket " $Global:CDRCounter
    #    for ($f = 2; $f -lt $Global:TicketForm.Length; $f++) {
    #      Write-Host $FieldsNames[$f]":" $Global:TicketForm[$f]
    #    }
    #
    # Short processed printout on console
    # "Sbs", "External", "Type", "StartDate", "StartTime", "Duration", "Waiting", "TG", "InitialNumber"
    $EAShortCDR = @()
    $EAShortCDR += $TicketForm[3]
    $EAShortCDR += $TicketForm[2]
    $EAShortCDR += $EACallTypes[$TicketForm[10]]
    $EAShortCDR += [datetime]::ParseExact($TicketForm[40].Split(" ")[0], ”yyyyMMdd”, $null).toshortdatestring()
    $EAShortCDR += $TicketForm[12].Split(" ")[1]
    $EAShortCDR += [timespan]::FromSeconds($TicketForm[15])
    $EAShortCDR += [timespan]::FromSeconds($TicketForm[37])
    $EAShortCDR += $TicketForm[17]
    $EAShortCDR += $TicketForm[36]
  }
  # Format of fields to CDR printout. Also could be generated by script.
  "|{0,8}|{1,20}|{2,4}|{3,11}|{4,9}|{5,9}|{6,9}|{7,5}|{8,20}|" -f $EAShortCDR[0], $EAShortCDR[1], $EAShortCDR[2] , $EAShortCDR[3], $EAShortCDR[4], $EAShortCDR[5], $EAShortCDR[6], $EAShortCDR[7], $EAShortCDR[8]
  $Global:TicketForm[2..($Global:TicketForm.Length)] -join "`t" | Out-File -Append $CDRFile -Encoding string
}
#
# Ethernet buffer size
# [byte[]]$Rcvbytes = 0..8192 | ForEach-Object {0xFF}
# For buffer processing purpose set it to 2048
# the larger the buffer the longer processing concerning TEST_REQ response. Leave to 4096.
[byte[]]$Rcvbytes = 0..4095 | ForEach-Object { 0xFF }
[Int]$PacketDelay = 250
# Intermediary buffer for processing
$data = $datastring = $NULL
#
# Errors declaration
#
# No connection to host
$EAErrorHost = 1
# Port 2533 is closed
$EAErrorPort = 2
# Wrong answer in Preamble
$EAErrorBytes = 3
# Role not Main
$EAErrorNotMain = 4
# Script already running
$EAScriptRunning = 5
# Ctrl-C pressed
$EAUserCtrlCPressed = 6
# Wrong data received
$EAWrongDataRcvd = 7
#
# set it for Ctrl-C hook
[console]::TreatControlCAsInput = $true
#
# Start-Transcript -Path Computer.log
# Here we go
# Print banner
Write-Host -ForegroundColor Yellow "Yet Another Ethernet Accounting Ticket Loader Script by Jeepers-Gitters@github.com. TABS2024® ©2024" 
# Check location where script runs
Write-Host "Running in $PSScriptRoot"
#
# Write-Debug -Message "This version runs in Powershell Version $($PSVersionTable.PSVersion.Major) "
# Check for INI file and set variables from it if exists
if ( Test-Path -Path $EAInitFile ) {
  $EAInitParams = Get-IniContent ($EAInitFile)
  if ( $EAInitParams.MainAddress.Debugging -eq 1 ) {
    $DebugPreference = "Continue"
  }
  else {
    $DebugPreference = "SilentlyContinue"
  }
if ( $EAInitParams.MainAddress.CPU1 ) {
  [ipaddress]$EAOXECPU1 = $EAInitParams.MainAddress.CPU1
  Write-Debug -Message "1st CPU defined $EAOXECPU1"
  }
# Check for CPU redundancy goes here
if ( $EAInitParams.MainAddress.CPU2 ) {
    [ipaddress]$EAOXECPU2 = $EAInitParams.MainAddress.CPU2
    Write-Debug -Message "2nd CPU defined $EAOXECPU2"
    $NeedToCheckMainCPU = $true
    $SpatialConfiguration = $true
  }
  else {
    Write-Debug -Message "No Duplication CPU-address defined"
    }
  $EATicketPort = $EAInitParams.MainAddress.Port
  $EACCFolder = $EAInitParams.MainAddress.WorkingDir
  if ( $EAInitParams.MainAddress.CDRPrint -eq 1 ) {
    $EALogEnable = $true
  }
  else {
    $EALogEnable = $false
  }
  if ( $EAInitParams.MainAddress.CDRPrint -eq 1 ) {
    $TicketPrintOut = $true
  }
  else {
    $TicketPrintOut = $false
  }
  if ( $EAInitParams.MainAddress.CDRBeep -eq 1 ) {
    $EACDRBeep = $true
  }
  else {
    $EACDRBeep = $false
  }
  Write-Host "Loaded parameters from $EAInitFile"
}
else {
  Write-Host "No $EAInitFile file found. Using default parameters."
}
#
# Change to Working Directory
Set-Location -Path $EACCFolder
$EALogFile = $EACCFolder + $DirSeparator + "log.txt"
# CDR ticket file
$CDRFile = $EACCFolder + $DirSeparator + $EAOXEMain + ".cdr"
# MAO tickets file
$MAOFile = $EACCFolder + $DirSeparator + $EAOXEMain + ".mao"
# VoIP quality tickets file
$VoIPFile = $EACCFolder + $DirSeparator + $EAOXEMain + ".voip"
#
# Check if already runnung
#
if (-not (Test-Path $EALockFile)) {
  New-Item -ItemType File -Path $EALockFile | Out-Null
}
else {
  Write-Host -ForegroundColor Red "Found $EALockFile. Looks like script already running or crashed. Exiting."
  exit $EAScriptRunning
}
# Re-enter here to restart in case of switchover
do {
Write-Debug -Message "Enter main loop $StartCounter"
# Get CPU addresses from CheckOXE
$EAOXEMain, $EAOXEStby = CheckOXE
Write-Debug -Message "Returned $EAOXEMain as Main $EAOXEStby as StandBy"
# Init Connection
$Client = New-Object System.Net.Sockets.TCPClient($EAOXEMain, $EATicketPort)
$Stream = $Client.GetStream()
$Client.ReceiveTimeout = $TCPReceiveTimeoutConnected
#
# Preamble
#
if ( $LogEnable ) {
  # Start logging in $EALogFile
    (Get-Date).toString("yyyy/MM/dd HH:mm:ss")  | Out-File -FilePath $EALogFile
}
$Stream.Write($InitMessage, 0, $InitMessage.Length)
$EAMessageCounter++
$i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)  
$data = [System.BitConverter]::ToString($i)
$datastring = [System.BitConverter]::ToString($Rcvbytes[0..($i - 1)])
$datastring | Format-Hex | Out-File   -FilePath $EALogFile -Append
Write-Debug -Message "$EAMessageCounter. Received $($data.Length) bytes : $datastring"

switch ($data.Length) {
  2 {
    if ($datastring -eq $StartMsg) {
      Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
      $i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
      $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
      $datastring = [System.BitConverter]::ToString($Rcvbytes[0..($i - 1)]) 
      $datastring | Format-Hex | Out-File   -FilePath $EALogFile -Append
      if ($datastring -eq $MainRole) {
        Write-Host -ForegroundColor Yellow "Role is Main. Link Established"
        Write-Host  "$([char]0x250D)-------------------------------------------------------------------------------------------------------$([char]0x2511)"
        "|{0,8}|{1,20}|{2,4}|{3,11}|{4,9}|{5,9}|{6,9}|{7,5}|{8,20}|" -f "Sbs", "External", "Type", "StartDate", "StartTime", "Duration", "Waiting", "TG", "InitialNumber"
        Write-Host  "$([char]0x2521)-------------------------------------------------------------------------------------------------------$([char]0x2525)"

      }
      else {
        Write-Host -ForegroundColor Red "Role is not Main $datastring `n"
        Write-Debug -Message "Disconnect." 
        $Stream.Flush()
        $Client.Close()
        Clear-LockFile
        exit $EAErrorNotMain
      }

    }
  }
  3 {
    if ($datastring -eq $ThreeBytesAnswer) {
      Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
      Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
    }
  }
  5 {
    if ($datastring -eq $FiveBytesAnswer) {
      Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
      Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
    }
  }

  default { 
    Write-Host "Too many bytes received."
    $Stream.Flush()
    $Client.Close()
    Clear-LockFile
    exit $EAErrorBytes 
  }
}

$Stream.Write($StartMessage, 0, $StartMessage.Length)
$TestKeepAlive = [System.Diagnostics.Stopwatch]::StartNew()
# $i - number of bytes received $datastring - binary bytes received $data - string representation
while (($i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)) -ne 0) {
  #  Write-Host -ForegroundColor Yellow "--- Wait for tickets" $Global:CDRCounter "/" $MAOCounter "/" $VOIPCounter
  $EAMessageCounter++
  # $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
  $data = [System.BitConverter]::ToString($Rcvbytes[0..($i - 1)]) 
  $datastring = ($Rcvbytes[0..($i - 1)])
  if ( $LogEnable ) {
    $datastring | Format-Hex | Out-File   -FilePath $EALogFile -Append
  }
  switch ($i) {
    1 {
      Write-Debug -Message "$($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')) Unknown command. Check logs."
      #$datastring = [System.BitConverter]::ToString($data)
    }
    2 {
      $datastring = $data
    }
    3 {
      #$datastring = [System.BitConverter]::ToString($data)
    }
    5 {
      #$datastring = [System.BitConverter]::ToString($data)
    }
    8 {
      #      $datastring = $data
      $datastring = [System.Text.Encoding]::UTF8.GetString($datastring)
    }

    # Single accounting ticket is of fixed size 772 bytes
    # Actually less (528) the rest is padded with "00"
    # MAO ticket is variable size but "packet" is still 772 bytes
    # If all types of tickets are send (mao, cdr, voip) then largely they are send in large buffers
    #
    # Buffer processing
    #
    #
    default {
      #$datastring = [System.Text.Encoding]::ASCII.GetString($data)
      $BufferBuffer = $datastring
      Write-Debug  -Message "Read Buffer: $($BufferBuffer.Length)"
      $StartPointer = 0
      $EAIterationCounter = 0
      $EALeftToProcess = $BufferBuffer.Length - $StartPointer

      if ( $EAKeepAliveReq ) {
        #
        #        [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + ($EATestRequest.Length - 1))])
        Start-Sleep -m $PacketDelay
        <#        $Stream.Write($TestReply, 0, $TestReply.Length)
        $EAMessageCounter++
        Start-Sleep -m $PacketDelay
        $Stream.Write($TestMessage, 0, $TestMessage.Length)
#>
        $Stream.Write($FullTestReply, 0, $FullTestReply.Length)

        Write-Debug -Message " $EATestReply sent"
        $EAKeepAliveReq = $false
        $StartPointer = ($StartPointer + $EATestRequest.Length)
      }
      if ( $TicketTruncated ) {
        #        $BufferBuffer = $TruncPart1 + $data
        $BufferBuffer = $TruncPart1 + $datastring
        Write-Debug -Message "Appended data from previous packets."
        $TicketTruncated = $false
        $TicketReady = $true
      }
      
      While ( $StartPointer -lt $BufferBuffer.Length ) {
        $EAIterationCounter++
        $datastring = [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + 1)])
        switch ( $datastring ) {
          $TicketReadyMark {
            $TicketReady = $true
            $StartPointer = $StartPointer + 2
          }
          $TicketMark {
            Write-Debug -Message "$($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')) Start buffer processing.."
          }
          $TestMark {
            Write-Debug -Message "$($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')) Test Command."
            # !? Need to test for the following TEST_REQ string here ?!
            # if ( [String]::new([char[]](($BufferBuffer[($StartPointer +2)..($BufferBuffer.Length)]))) -eq "TEST_REQ" )
            <# Insert an answer to TEST_REQ here instead of wait till end of processing #>
            $EAKeepAliveReq = $true
            Start-Sleep -m $PacketDelay
            $Stream.Write($FullTestReply, 0, $FullTestReply.Length)
            Write-Debug -Message "$($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')) $EATestReply sent"
            $EAKeepAliveReq = $false
            $StartPointer = $StartPointer + 10
            $datastring = $NoOperation
          }
          default {
            Write-Host -ForegroundColor Red "Wrong data...Check logs. $datastring "
            exit $EAWrongDataRcvd
          }
        }
        #
        # Load one ticket record into $data variable
        $data = $BufferBuffer[$StartPointer..($StartPointer + $TicketMessageLength)]
        #
        # convert this record to ASCII, all 00's would be truncated
        # only works for CDR and MAO tickets as they are printable format
        # for VoIP tickects it distorts data, e.g. C0 is converted to 3F (?)
        $ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
        $EALeftToProcess = $BufferBuffer.Length - $StartPointer
        Write-Debug -Message " $EAIterationCounter Pointer:$StartPointer Left:$EALeftToProcess Length:$($BufferBuffer.Length) "
        #        Write-Debug -Message "$EALeftToProcess left to process"
        if ( ($EALeftToProcess -lt $TicketMessageLength) -and ($TicketReady)) {
          Write-Debug -Message "Bytes left:$EALeftToProcess . Next ticket is truncated."
          $TicketTruncated = $true
          $TruncPart1 = $data
        }
        If ($TicketReady) {

          $TicketFlag = [System.BitConverter]::ToString($ProcessTicket[0..3])
          if ( $TicketFlag ) {
            #            Write-Host <# -NoNewline #> "  Ticket Flag is " $TicketFlag " "
          }
          else {
            $TicketFlag = "NOP"
          }
          switch ($TicketFlag) {
            $EmptyTicket {
              $TicketReady = $false
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            $BufferTest {
              Write-Host -ForegroundColor Cyan "Test_REQ received in buffer -1."
              <#        Start-Sleep -m $PacketDelay
            $Stream.Write($TestReply, 0, $TestReply.Length)
            Start-Sleep -m $PacketDelay
            $Stream.Write($TestMessage, 0, $TestMessage.Length)
            $EAMessageCounter++
            Write-Debug -Message "$EAMessageCounter. Reply with TEST_RSP -2 "
            Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss') #>
              $TicketTruncated = $false
              $TicketReady = $false
              $StartPointer = $BufferBuffer.Length
              #$StartPointer = $StartPointer + $EATestRequest.Length
              $datastring = $EATestRequest
            }
            $MAOTicket {
              #Write-Debug -Message " MAO Ticket"
              $MAOdata = $ProcessTicket.Substring(4, $ProcessTicket.IndexOf(0x0a) - 4) -replace ("=", "`t") | Out-File -Append $MAOFile
              $MAOdata = $MAOdata -replace ".{1}$" -Split ";"
              if ( $TicketPrintOut ) {
                Foreach ($MAOLine in $MAOdata) {
                  $MAOField = $MAOLine.Split("`t")
                  Write-Host $MAOfield[0] $MAOField[1] ":" $MAOField.Count
                }
              }
              $MAOCounter++
              $TicketReady = $false
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            $VoIPTicket { 
              #            Write-Debug -Message " VoIP Ticket"
              if ( $PSVersionTable.PSVersion.Major -lt 6 ) {
                Add-Content -Path $VoIPFile -Value $data[4..$data.Length] -Encoding Byte
                }
                   else {
                      Add-Content -Path $VoIPFile -Value $data -AsByteStream
                      }
              $VoIPCounter++
              $TicketReady = $false
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            $CDRTicket {
              if ( -Not ($TicketTruncated) ) {
                if ( $EACDRBeep ) { [System.Console]::Beep() }
                ProcessOneTicket
                $TicketReady = $false
              }
              else {
                # !!! check this empty condition
              }
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            "NOP" {
              Write-Debug -Message "Buffer processed. Skipping.."
            } 
            default {
              Write-Host -ForegroundColor Red "Unknown ticket type. Check $EALogFile. $TicketFlag"
            }

          }
        }
        #  Write-Host $StartPointer "vs" $BufferBuffer.Length
        #        }
      } # closing bracket for line 322

    }
  }

  Write-Debug -Message "$($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')) Received $($i) bytes."
  switch ($datastring) {
    $TicketReadyMark {
      Write-Debug -Message "Ticket Ready."
      $TicketReady = $true
    }
    $TestMark {
      Write-Debug -Message "Test Command."
      $EAKeepAliveReq = $true
    }
    $EATestRequest {
      Write-Debug -Message "$EATestRequest received"
      if ($EAKeepAliveReq) {
        Start-Sleep -m $PacketDelay
        $Stream.Write($FullTestReply, 0, $FullTestReply.Length)
        Write-Debug -Message " $EATestReply sent"
        #        Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
        $EAKeepAliveReq = $false
        #        Write-Host -NoNewLine "`r Tickets received: $Global:CDRCounter, $MAOCounter, $VOIPCounter Uptime: $($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss'))" "`r"
      } 
    }
    "Ticket Info" {
      #      Write-Host  "Tickets received: $Global:CDRCounter, $MAOCounter, $VOIPCounter Uptime: $($TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss'))"
    }
    default {
      if (($datastring.Length -lt $TicketMessageLength) -and ($datastring.Length -gt 0)) {
        Write-Host -ForegroundColor Red "Unknown command :" $datastring.Length  "-"  $datastring "Log written."
        if ( $LogEnable ) {
          $datastring | Format-Hex | Out-File   -FilePath $EALogFile -Append
        }
      }
      else {
        Write-Debug -Message "Buffer processing.."
      }
    }
  }
  If ($Host.UI.RawUI.KeyAvailable -and ($Key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
    If ([Int]$Key.Character -eq 3) {
      Write-Host ""
      Write-Host "CTRL-C pressed. Stopping script..."
      $Stream.Flush()
      $Client.Close()
      Clear-LockFile
      exit $EAUserCtrlCPressed
      }
    }
}
#
# 
#
if ( -Not (Get-NetTCPConnection -State Established -RemotePort $EATicketPort -ErrorAction SilentlyContinue) ) {
#if ( -Not (Get-NetTCPConnection -State Established -RemotePort $EATicketPort ) ) {
  Write-Debug -Message "Connection closed from server."
}
$EAUptime = $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
$Stream.Flush()
$Client.Close()
if ( $SpatialConfiguration )  {
  Write-Debug -Message "Possible CPU switch over from $EAOXEMain to $EAOXEStby"
  if  ( Test-Connection $EAOXEStby -Count 1 -Quiet   ) {
    $EAOXEMain = $EAOXEStby
    Write-Host -ForegroundColor Yellow "New Main CPU $EAOXEMain"
    Write-Host -ForegroundColor Red "Restarting script!"
    }
  }
#
# do while switchover
# wait for 10 seconds for switchover just to settle things down
  Start-Sleep -Seconds 10
  $StartCounter++
}
#
# Actually check $SpatialConfiguration is excessive here
while ( $SpatialConfiguration -or $CPUSwitchover )

Write-Debug -Message "Disconnect from $EAOXEMain. Uptime $EAUptime  Tickets received: $Global:CDRCounter, $MAOCounter, $VOIPCounter"
Clear-LockFile
Write-Host "Done."