#Requires -Version 5
# version 0.9
# v.3 - add large buffer processing
# v.4 - remove single message processing and use universal for shorter code
#     - added TEST_REQ processing in large buffer
#     - change reply to TEST_REQ handling
Param(
  #    [Parameter(Mandatory = $true, HelpMessage = "Enter Main role CPU address here", Alias("ADDR","A") )]
  $OXEMain = "192.168.92.52",
  # $OXEMain = "192.168.50.18",
  #    [Parameter(Mandatory = $false, HelpMessage = "Enter netaccess Port here")]
  $TicketPort = 2533,
  #    [Parameter(Mandatory = $false, Switch)]
  $LogEnable
)

# Working Directory for testing
$EACCFolder = "C:\Temp\EACC\"

# Log file
$LogEnable = $true
$TicketPrintOut = $false
$LogFile = $EACCFolder + "log.txt"
# CDR file
$CDRFile = $EACCFolder + $OXEMain + ".cdrs"
$MAOFile = $EACCFolder + $OXEMain + ".mao"
$VoIPFile = $EACCFolder + $OXEMain + ".voip"
$TicketFields = @(4, 5, 30, 30, 20, 10, 16, 5, 20, 30, 2, 1, 17, 5, 10, 10, 5, 5, 5, 1, 16, 7, 1, 2, 10, 5, 40, 40, 10, 10, 10, 10, 1, 2, 2, 2, 30, 5, 10, 1, 17, 30, 5, 5, 5, 5, 5, 6, 6)
$TicketMessageLength = 772
$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$TicketMark = "01-00"
# when CDR buffer is very long TEST_REQ is sent in Buffer
$BufferTest = "00-08-54-45"
$EmptyTicket = "01-00-01-00"
$CDRTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$VoIPTicket = "01-00-07-00"
$TicketInfo = "03-04"
$TicketTruncated = $false
$Global:CDRCounter = 0
$Global:TicketForm = @()
$StartPointer = 0


function CheckOXE {
  Write-Host  -NoNewline "Host $OXEMain reachable : "
		if ( Test-Connection $OXEMain -Count 1 -Quiet   ) {
				Write-Host -ForegroundColor Green "OK"
  }
  else {
    Write-Host -ForegroundColor Red "NOK"
    Write-Host "Exiting. Check network connection."
    exit $ErrorHost
  }
  # (Test-NetConnection $OXEMain  -Port $TicketPort).TcpTestSucceeded
  Write-Host -NoNewline "Connection on $OXEMain" port "$TicketPort : "
  $Client = New-Object System.Net.Sockets.TCPClient($OXEMain, $TicketPort)
  $Stream = $Client.GetStream()
  $Client.ReceiveTimeout = 31000;

  if ( $Client.Connected ) {
    #        if ( (Test-NetConnection -ComputerName $OXEMain -Port $TicketPort ).TcpTestSucceeded )
    #
    #       $EAConnected = $true
    Write-Host -ForegroundColor Green "OK`n"
  }
  else {
    Write-Host -ForegroundColor Red "NOK"
    Write-Host "Exiting. Ethernet Account port closed on $OXEMain."
    exit $ErrorPort
  }
  $Client.Close()
}

function ProcessOneTicket() {
  Write-Host "SMDR Ticket. The length is "  $ProcessTicket.Length
  $Global:TicketForm = @(
    $TicketFields | Select-Object | ForEach-Object {
      $ProcessTicket.Remove($_)
      $ProcessTicket = $ProcessTicket.Substring($_)
    }
  )

  $Global:CDRCounter++

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



[INT32]$MsgCounter = 1
$StartMsg = "00-01"
$MainCPU = "50"
$ThreeBytesAnswer = $StartMsg + "-" + $MainCPU
$FiveBytesAnswer = $ThreeBytesAnswer + "-" + $TicketInfo
$ACKMessageStr = "03-04"
$TestRequest = "TEST_REQ"
[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02, 0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x08
[Byte[]]$TestMessage = 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
# Ethernat buffer size
# Info received in this buffer sizes
#[byte[]]$Rcvbytes = 0..8192 | ForEach-Object {0xFF}

#
# For buffer processing purpose set it to 2048
[byte[]]$Rcvbytes = 0..4096 | ForEach-Object { 0xFF }
[Int]$PacketDelay = 500
$data = $datastring = $NULL
[Int]$MAOCounter = 0
[Int]$VOIPCounter = 0
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

# Write-Host $FieldsNames.Length  "fields in 5.2 version"
#
# Check connection and port
#
CheckOXE

# Init Connection
$Client = New-Object System.Net.Sockets.TCPClient($OXEMain, $TicketPort)
$Stream = $Client.GetStream()
$Client.ReceiveTimeout = 31000;

#
# Preamble
#
#Write-Host "Init Phase"
if ( $LogEnable ) {
  Write-Host "Start logging in $LogFile"
    (Get-Date).toString("yyyy/MM/dd HH:mm:ss")  | Out-File -FilePath $LogFile
}
$Stream.Write($InitMessage, 0, $InitMessage.Length)
$MsgCounter++
#Start-Sleep -m $PacketDelay
$i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
$data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
$datastring = [System.BitConverter]::ToString($data)

#Write-Host "$MsgCounter. Received $($data.Length) bytes : $datastring"

switch ($data.Length) {
  2 {
    #            Write-Host -NoNewLine "Got 2 bytes "
    if ($datastring -eq $StartMsg) {
      Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
      $i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
      $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
      $datastring = [System.BitConverter]::ToString($data)
      #                Write-Host "$MsgCounter. Received $($data.Length) bytes : $datastring"
      if ($datastring -eq "50") {
        Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
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
$MsgCounter++
$TestKeepAlive = [System.Diagnostics.Stopwatch]::StartNew()

while (($i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)) -ne 0) {
  Write-Host -ForegroundColor Yellow "--- Wait for tickets" $Global:CDRCounter "/" $MAOCounter "/" $VOIPCounter
  $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes, 0, $i)
  if ( $LogEnable ) {
    $data | Format-Hex | Out-File   -FilePath $LogFile -Append
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
    #


    # Buffer processing
    #
    default {
      $datastring = [System.Text.Encoding]::ASCII.GetString($data)
      $BufferBuffer = $data
      Write-Host "Read buffer:" $BufferBuffer.Length
      if ( $TicketTruncated ) {
        $BufferBuffer = $TruncPart1 + $data
        Write-Host "Appended data left from previous packets."
        $TicketTruncated = $false
      }
      $StartPointer = 0

      While ( $StartPointer -lt $BufferBuffer.Length ) {
        $datastring = [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + 1)])
        switch ( $datastring ) {
          $TicketInfo {
            Write-Host "Continue buffer processing ..."
            $TicketReady = $true

            $StartPointer++
            $StartPointer++
          }
          $TicketMark {
            Write-Host "Start buffer processing.."
          }
          default {
            Write-Host "Wrong data...Check logs."
          }
        }

        #
        # Load one ticket record into $data variable
        $data = $BufferBuffer[$StartPointer..($StartPointer + $TicketMessageLength)]
        #
        # convert this record to ASCII
        $ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
        Write-Host "Buffer Pointer:" $StartPointer "/" $BufferBuffer.Length "/" ($BufferBuffer.Length - $StartPointer)
        $LeftToProcess = $BufferBuffer.Length - $StartPointer

        if ( $LeftToProcess -lt $TicketMessageLength ) {
          Write-Host "Bytes left :" $LeftToProcess ". Next ticket is truncated."
          $TicketTruncated = $true
          $TruncPart1 = $data
        }
        # If ($TicketReady)

        $TicketFlag = [System.BitConverter]::ToString($ProcessTicket[0..3])
        Write-Host -NoNewline "Ticket Flag is " $TicketFlag " "
        switch ($TicketFlag) {
          $EmptyTicket {
            Write-Host "Empty Ticket"
            $TicketReady = $false
          }
          $BufferTest {
            Write-Host -ForegroundColor Red "Test_REQ received in buffer."
            #        Start-Sleep -m $PacketDelay
            $Stream.Write($TestReply, 0, $TestReply.Length)
            $MsgCounter++
            Start-Sleep -m $PacketDelay
            $Stream.Write($TestMessage, 0, $TestMessage.Length)
            $MsgCounter++
            Write-Host "$MsgCounter. Reply with TEST_RSP"
            Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
            $TicketTruncated = $false
          }
          $MAOTicket {
            Write-Host "MAO Ticket"
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
          }
          $CDRTicket {
            if ( -Not ($TicketTruncated) ) {
              [System.Console]::Beep()
              ProcessOneTicket
            }
            else {
              Write-Host " Waiting for the rest of ticket..."
            }
            $TicketReady = $false
          }

          default {
            Write-Host "Unknown ticket type. Check $LogFile."
          }

        }

        $StartPointer = $StartPointer + $TicketMessageLength


        Write-Host "Buffer processing.. $Global:CDRCounter tickets processed "
      }
      #  Write-Host $StartPointer "vs" $BufferBuffer.Length
      # Проверка на длину буфера закрывающая скобка
      #        }
      $datastring = "Ticket Info"

    }
  }

  Write-Host -NoNewLine "$MsgCounter. Received $($data.Length) bytes:"
  # $datastring

  switch ($datastring) {
    $ACKMessageStr {
      Write-Host "Ticket Ready Command"
      $TicketReady = $true
    }
    "00-08" {
      Write-Host "Test Request Command"
      $KeepAliveReq = $true
      #     $Stream.Write($TestReply, 0, $TestReply.Length)
      #     $MsgCounter++
    }
    $TestRequest {
      Write-Host "Test Request String"
      if ($KeepAliveReq) {
        Start-Sleep -m $PacketDelay
        $Stream.Write($TestReply, 0, $TestReply.Length)
        $MsgCounter++
        Start-Sleep -m $PacketDelay
        $Stream.Write($TestMessage, 0, $TestMessage.Length)
        $MsgCounter++
        Write-Host "$MsgCounter. Reply with TEST_RSP"
        Write-Host -ForegroundColor Green "--- Runtime" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
      } 
    }
    "Ticket Info" {
      Write-Host "Ticket Information"
    }
    default {
      if ($datastring.Length -lt 772) {
        Write-Host -ForegroundColor Red "Unknown command :" $datastring.Length  "-"  $datastring "Log written."
        if ( $LogEnable ) {
          $datastring | Format-Hex | Out-File   -FilePath $LogFile -Append
        }
      }
      else {
        Write-Host "Buffer processing.."

      }
    }
  }


  $MsgCounter++

}

#
# Main body
#
if ( -Not (Get-NetTCPConnection -State Established -RemotePort $TicketPort -ErrorAction SilentlyContinue) ) {
  Write-Host "Connection closed from server."
}
Write-Host "Disconnect." "Uptime: " $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss') "Tickets received :" $Global:CDRCounter
$Stream.Flush()
$Client.Close()
