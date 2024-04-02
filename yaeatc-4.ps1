#Requires -Version 5
# version 0.6
#     - add large buffer processing
#     - remove single message processing and use universal for shorter code
#     - added TEST_REQ processing in large buffer
#     - change reply to TEST_REQ handling
#     - some messages (Write-Host) are commented out to speed up processing
#     - added VoIP tickets saving (needs correction)
#     - TEST_REQ handling corrected  (in the middle of buffer)
#     - TEST_REQ handling corrected  (at the end of the buffer)
#     ? Check for TEST_REQ at the start of bueffer needed when 00 08 sent separately
#     - "Unknown ticket type" when StartPoiner is equal BufferBuffer.Length.
#     - Reply to TEST_REQ with one message $FullTestReply not two consecutive messages
#     ? Check with Stand-by CPU address and with physical main CPU address
#     ? Send an ACK to every ticket
#     - added ini file loading
#     ? iteration counter reset on new buffer
#     ? add return values to CheckOXE function
#     - change EAMessageCounter to received buffers
<#
.SYNOPSIS
  Receives CDR tickets on Ethernet from Alcatel-Lucent OmniPCX Enterprise
.DESCRIPTION
  This script uses ALU netaccess protocol for receiving real-time tickets on Ethernet. All received tickets without
  any processing are written to appropriate files.
#>

Param(
  [Alias ("addr", "main")]
  [Parameter ( Position = 0, Mandatory = $false, HelpMessage = "Enter Main role CPU address here" )] $EAOXEMain = "192.168.50.18",
  #$EAOXEMain = "192.168.50.18",
  
  [Alias ("port")]
  [Parameter (Position = 1, Mandatory = $false, HelpMessage = "Enter netaccess Port here")]
  $EATicketPort = 2533,
  
  [Alias ("log")]
  [Parameter (Mandatory = $false )]
  [Switch] $LogEnable 
)


# Working Directory for testing
$EACCFolder = "C:\Temp\EACC\"
# Ini file
$EAIniFile = $EACCFolder + "eacc.ini"
$EALogFile = $EACCFolder + "log.txt"
# CDR file
$CDRFile = $EACCFolder + $EAOXEMain + ".cdrs"
$MAOFile = $EACCFolder + $EAOXEMain + ".mao"
$VoIPFile = $EACCFolder + $EAOXEMain + ".voip"
$TicketFields = @(4, 5, 30, 30, 20, 10, 16, 5, 20, 30, 2, 1, 17, 5, 10, 10, 5, 5, 5, 1, 16, 7, 1, 2, 10, 5, 40, 40, 10, 10, 10, 10, 1, 2, 2, 2, 30, 5, 10, 1, 17, 30, 5, 5, 5, 5, 5, 6, 6)
$TicketMessageLength = 772
$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$TicketMark = "01-00"
$TestMark = "00-08"
$BufferTest = "00-08-54-45"
$EmptyTicket = "01-00-01-00"
$CDRTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$VoIPTicket = "01-00-07-00"
$TicketReadyMark = "03-04"
$TestRequest = "TEST_REQ"
$TicketTruncated = $false
$Global:CDRCounter = 0
$Global:TicketForm = @()
$BufferBuffer = @()
$StartPointer = 0
$EAIterationCounter = 0 
$EALeftToProcess = 0 
$TicketPrintOut = $false


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

function CheckOXE {
  Write-Host  -NoNewline "Host $EAOXEMain reachable : "
		if ( Test-Connection $EAOXEMain -Count 1 -Quiet   ) {
				Write-Host -ForegroundColor Green "OK"
  }
  else {
    Write-Host -ForegroundColor Red "NOK"
    Write-Host "Exiting. Check network connection."
    exit $ErrorHost
  }
  # (Test-NetConnection $EAOXEMain  -Port $EATicketPort).TcpTestSucceeded
  Write-Host -NoNewline "Connection on $EAOXEMain" port "$EATicketPort : "
  $Client = New-Object System.Net.Sockets.TCPClient($EAOXEMain, $EATicketPort)
  $Stream = $Client.GetStream()
  $Client.ReceiveTimeout = 31000;

  if ( $Client.Connected ) {
    #        if ( (Test-NetConnection -ComputerName $EAOXEMain -Port $EATicketPort ).TcpTestSucceeded )
    #
    #       $EAConnected = $true
    Write-Host -ForegroundColor Green "OK`n"
  }
  else {
    Write-Host -ForegroundColor Red "NOK"
    Write-Host "Exiting. Ethernet Account port closed on $EAOXEMain."
    exit $ErrorPort
  }
  $Client.Close()
}

function ProcessOneTicket() {
  #  Write-Host "SMDR Ticket. The length is "  $ProcessTicket.Length
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
    Write-Host -ForegroundColor Yellow   "--- Ticket " $Global:CDRCounter
    for ($f = 2; $f -lt $Global:TicketForm.Length; $f++) {
      Write-Host $FieldsNames[$f]":" $Global:TicketForm[$f]
    }
  }
  $Global:TicketForm[2..($Global:TicketForm.Length)] -join "`t" | Out-File -Append $CDRFile
}



[INT32]$EAMessageCounter = 0
$StartMsg = "00-01"
$MainRole = "50"
$ThreeBytesAnswer = $StartMsg + "-" + $MainRole
$FiveBytesAnswer = $ThreeBytesAnswer + "-" + $TicketReadyMark

[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02, 0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x08
[Byte[]]$TestMessage = 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
$FullTestReply = $TestReply + $TestMessage

#
# Ethernet buffer size
# [byte[]]$Rcvbytes = 0..8192 | ForEach-Object {0xFF}
#
# For buffer processing purpose set it to 2048
# the larger the buffer the longer processing concerning TEST_REQ response. Leave to 4096.
[byte[]]$Rcvbytes = 0..4096 | ForEach-Object { 0xFF }
[Int]$PacketDelay = 250
$data = $datastring = $NULL
[Int32]$MAOCounter = 0
[Int32]$VOIPCounter = 0
$TicketReady = $false
#
# Errors declaration
#
# No connection to host
$ErrorHost = 1
# Port 2533 is closed
$ErrorPort = 2
# Wrong answer in Preamble
$ErrorBytes = 3
# Role not Main
$ErrorNotMain = 4



# Check fo INI file
if ( Test-Path -Path $EAIniFile ) {
  Write-Host " Loading data from $EAIniFile.. "
  $EAInitParams = Get-IniContent ($EAIniFile)
  $EAOXEMain = $EAInitParams.MainAddress.CPU
  $EATicketPort = $EAInitParams.MainAddress.Port
  $EACCFolder = $EAInitParams.MainAddress.WorkingDir
  if ( $EAInitParams.MainAddress.Logging ) {
    $LogEnable = $true
  }
}
else {
  Write-Host " No ini file found. Using default parameters."
}
#
#
Write-Host " Host is $EAOXEMain on port $EATicketPort with logging = $LogEnable in $EACCFolder"

#
# Check connection and port
#
CheckOXE
# Init Connection
$Client = New-Object System.Net.Sockets.TCPClient($EAOXEMain, $EATicketPort)
$Stream = $Client.GetStream()
$Client.ReceiveTimeout = 31000;
#
# Preamble
#
#Write-Host "Init Phase"
if ( $LogEnable ) {
  #  Write-Host "Start logging in $EALogFile"
    (Get-Date).toString("yyyy/MM/dd HH:mm:ss")  | Out-File -FilePath $EALogFile
}
$Stream.Write($InitMessage, 0, $InitMessage.Length)
$EAMessageCounter++
#Start-Sleep -m $PacketDelay
$i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
$data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
$data | Format-Hex | Out-File   -FilePath $EALogFile -Append
$datastring = [System.BitConverter]::ToString($data)

#Write-Host "$EAMessageCounter. Received $($data.Length) bytes : $datastring"

switch ($data.Length) {
  2 {
    #            Write-Host -NoNewLine "Got 2 bytes "
    if ($datastring -eq $StartMsg) {
      Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
      $i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
      $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
      $data | Format-Hex | Out-File   -FilePath $EALogFile -Append
      $datastring = [System.BitConverter]::ToString($data)
      if ($datastring -eq $MainRole) {
        Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
      }
      else {
        Write-Host -ForegroundColor Red "Role is not Main  `n"
        Write-Host "Disconnect." 
        $Stream.Flush()
        $Client.Close()
        exit $ErrorNotMain
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
      Write-Host -ForegroundColor Yellow "Getting ticket."
    }
  }

  default { exit $ErrorBytes }
}
$Stream.Write($StartMessage, 0, $StartMessage.Length)
#$EAMessageCounter++
$TestKeepAlive = [System.Diagnostics.Stopwatch]::StartNew()

while (($i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)) -ne 0) {
  #  Write-Host -ForegroundColor Yellow "--- Wait for tickets" $Global:CDRCounter "/" $MAOCounter "/" $VOIPCounter
  $EAMessageCounter++
  $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)

  if ( $LogEnable ) {
    $data | Format-Hex | Out-File   -FilePath $EALogFile -Append
  }

  switch ($data.Length) {
    1 {
      Write-Host "Unknown command. Check logs."
      $datastring = [System.BitConverter]::ToString($data)
    }
    2 {
      $datastring = [System.BitConverter]::ToString($data)
    }
    3 {
      $datastring = [System.BitConverter]::ToString($data)
    }
    5 {
      $datastring = [System.BitConverter]::ToString($data)
    }
    8 {
      $datastring = [System.Text.Encoding]::UTF8.GetString($data)
    }

    # Single accounting ticket is of fixed size 772 bytes
    # Actually less (528) the rest is padded with "00"
    # MAO ticket is variable size but "packet" is still 772 bytes
    # If all types of tickets are send (mao, cdr, voip) then largely they are send inlarge buffers
    #
    # Buffer processing
    #
    #
    default {
      $datastring = [System.Text.Encoding]::ASCII.GetString($data)
      $BufferBuffer = $data
      Write-Host "Read buffer:" $BufferBuffer.Length
      $StartPointer = 0
      $EAIterationCounter = 0
      $EALeftToProcess = $BufferBuffer.Length - $StartPointer

      if ( $KeepAliveReq ) {
        #
        #        [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + ($TestRequest.Length - 1))])
        Start-Sleep -m $PacketDelay
        <#        $Stream.Write($TestReply, 0, $TestReply.Length)
        $EAMessageCounter++
        Start-Sleep -m $PacketDelay
        $Stream.Write($TestMessage, 0, $TestMessage.Length)
#>
        $Stream.Write($FullTestReply, 0, $FullTestReply.Length)

        Write-Host ' Reply with $FullTestReply'
        Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
        $KeepAliveReq = $false
        $StartPointer = ($StartPointer + $TestRequest.Length)
      }
      if ( $TicketTruncated ) {
        $BufferBuffer = $TruncPart1 + $data
        Write-Host "Appended data from previous packets."
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
            Write-Host " Start buffer processing.."
          }
          $TestMark {
            Write-Host -ForegroundColor Cyan "Test Request."
            # !? Need to test for TEST_REQ string here ?!
            # if ( [String]::new([char[]](($BufferBuffer[($StartPointer +2)..($BufferBuffer.Length)]))) -eq "TEST_REQ" )
            <# Insert an answer to TEST_REQ here instead of wait till end of processing  
#>
            $KeepAliveReq = $true
            Start-Sleep -m $PacketDelay
            $Stream.Write($FullTestReply, 0, $FullTestReply.Length)
            Write-Host ' Reply with $FullTestReply'
            Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
            $KeepAliveReq = $false
            $StartPointer = $StartPointer + 10
            $datastring = $NoOperation
          }
          default {
            Write-Host -ForegroundColor Red "Wrong data...Check logs. $datastring "
          }
        }

        #
        # Load one ticket record into $data variable
        $data = $BufferBuffer[$StartPointer..($StartPointer + $TicketMessageLength)]
        #
        # convert this record to ASCII, all 00's would be truncated
        $ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
        $EALeftToProcess = $BufferBuffer.Length - $StartPointer
        Write-Host "$EAIterationCounter Buffer Pointer:" $StartPointer "/" $EALeftToProcess "/" $BufferBuffer.Length 
        #        Write-Host "$EALeftToProcess left to process"
        if ( ($EALeftToProcess -lt $TicketMessageLength) -and ($TicketReady)) {
          Write-Host "Bytes left :" $EALeftToProcess ". Next ticket is truncated."
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
              Write-Host " Empty Ticket"
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
            Write-Host "$EAMessageCounter. Reply with TEST_RSP -2 "
            Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss') #>
              $TicketTruncated = $false
              $TicketReady = $false
              $StartPointer = $BufferBuffer.Length
              #$StartPointer = $StartPointer + $TestRequest.Length
              $datastring = $TestRequest
            }
            $MAOTicket {
              #            Write-Host " MAO Ticket"
              $MAOdata = $ProcessTicket.Substring(4, $ProcessTicket.IndexOf(0x0a) - 4) -replace ("=", "`t") | Out-File -Append $MAOFile
              $MAOdata = $MAOdata -replace ".{1}$" -Split ";"
              if ( $TicketPrintOut ) {
                Foreach ($MAOLine in $MAOdata) {
                  $MAOField = $MAOLine.Split("`t")
                  Write-Host $MAOfield[0] $MAOField[1] ":" $MAOField.Count
                }
              }
              #            $MAOdata | Out-File -Append $MAOFile
              $MAOCounter++
              $TicketReady = $false
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            $VoIPTicket { 
              #            Write-Host " VoIP Ticket"
              $ProcessTicket | Out-File -Append $VoIPFile
              $VoIPCounter++
              $TicketReady = $false
              $StartPointer = $StartPointer + $TicketMessageLength
              $datastring = "Ticket Info"
            }
            $CDRTicket {
              if ( -Not ($TicketTruncated) ) {
                [System.Console]::Beep()
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
              Write-Host "Buffer processed. Skipping.."
            } 
            default {
              Write-Host -ForegroundColor Red "Unknown ticket type. Check $EALogFile. $TicketFlag"
            }

          }

          #       $StartPointer = $StartPointer + $TicketMessageLength


          #  Write-Host "Buffer processing.. $Global:CDRCounter tickets processed "
        }
        #  Write-Host $StartPointer "vs" $BufferBuffer.Length
        # Проверка на длину буфера закрывающая скобка
        #        }
      } # closing bracket for line 322
      #$datastring = "Ticket Info"

    }
  }

  Write-Host <# -NoNewLine  "$EAMessageCounter.#> "Received $($data.Length) bytes:"
  # $datastring

  switch ($datastring) {
    $TicketReadyMark {
      Write-Host "Ticket Ready."
      $TicketReady = $true
    }
    $TestMark {
      Write-Host "Test Request."
      $KeepAliveReq = $true
    }
    $TestRequest {
      Write-Host "Test Request String"
      if ($KeepAliveReq) {
        Start-Sleep -m $PacketDelay
        <#
        $Stream.Write($TestReply, 0, $TestReply.Length)
        $EAMessageCounter++
        Start-Sleep -m $PacketDelay
        $Stream.Write($TestMessage, 0, $TestMessage.Length)
#>
        $Stream.Write($FullTestReply, 0, $FullTestReply.Length)
        Write-Host ' Reply with $FullTestReply'
        Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
        $KeepAliveReq = $false
      } 
    }
    "Ticket Info" {
      Write-Host -Foreground Magenta "Tickets received: $Global:CDRCounter, $MAOCounter, $VOIPCounter"
    }
    default {
      if (($datastring.Length -lt 772) -and ($datastring.Length -gt 0)) {
        Write-Host -ForegroundColor Red "Unknown command :" $datastring.Length  "-"  $datastring "Log written."
        if ( $LogEnable ) {
          $datastring | Format-Hex | Out-File   -FilePath $EALogFile -Append
        }
      }
      else {
        Write-Host "Buffer processing.."

      }
    }
  }
}

#
# Main body
#
if ( -Not (Get-NetTCPConnection -State Established -RemotePort $EATicketPort -ErrorAction SilentlyContinue) ) {
  Write-Host "Connection closed from server."
}
Write-Host "Disconnect." "Uptime: " $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss') "Tickets received: $Global:CDRCounter, $MAOCounter, $VOIPCounter"
$Stream.Flush()
$Client.Close()
