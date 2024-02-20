# version 1.9
# add large buffer processing
Param(
#    [Parameter(Mandatory)]
    $OXEMain = "192.168.92.52",
    $TicketPort = 2533
)

# Working Directory
$EACCFolder = "C:\Temp\EACC\"
# Log file
$LogFile = $EACCFolder + "log.txt"
# CDR file
$CDRFile =  $EACCFolder + $OXEMain + "_CDRs.txt"
$TicketFields = @(4,5,30,30,20,10,16,5,20,30,2,1,17,5,10,10,5,5,5,1,16,7,1,2,10,5,40,40,10,10,10,10,1,2,2,2,30,5,10,1,17,30,5,5,5,5,5,6,6)
$TicketMessageLength = 772
$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$TicketMark = "01-00"
$EmptyTicket = "01-00-01-00"
$NormalTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$TcktVersion = "ED5.2"
$TicketInfo = "03-04"
$FieldsCounter = 1
$TicketTruncated = $false

$StartPointer = 0


function Check-OXE
{
    Write-Host  -NoNewline "Host $OXEMain reachable : "
		if ( Test-Connection $OXEMain -Count 1 -Quiet   )
			{
				Write-Host -ForegroundColor Green "OK"
			}
        else
            {
                Write-Host -ForegroundColor Red "NOK"
                Write-Host "Exiting. Check network connection."
                exit $ErrorHost
            }
# (Test-NetConnection $OXEMain  -Port $TicketPort).TcpTestSucceeded
    Write-Host -NoNewline "Connection on $OXEMain" port "$TicketPort : "
    $Client = New-Object System.Net.Sockets.TCPClient($OXEMain,$TicketPort)
    $Stream = $Client.GetStream()
    $Client.ReceiveTimeout = 31000;

        if ( $Client.Connected )
#        if ( (Test-NetConnection -ComputerName $OXEMain -Port $TicketPort ).TcpTestSucceeded )
        {
 #
 #       $EAConnected = $true
        Write-Host -ForegroundColor Green "OK`n"
        }
        else
            {
        Write-Host -ForegroundColor Red "NOK"
        Write-Host "Exiting. Ethernet Account port closed on $OXEMain."
        exit $ErrorPort
            }
    $Client.Close()
}

[INT32]$MsgCounter = 1
$StartMsg = "00-01"
$MainCPU = "50"
$ThreeBytesAnswer = $StartMsg + "-" + $MainCPU
$FiveBytesAnswer = $ThreeBytesAnswer + "-" + $TicketInfo
$ACKMessageStr = "03-04"
$TestRequest = "TEST_REQ"
[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02,0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x08
[Byte[]]$TestMessage = 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
# Ethernat buffer size
# Info received in this buffer sizes
#[byte[]]$Rcvbytes = 0..8192 | ForEach-Object {0xFF}

#
# For buffer processing purpose set it to 2048
[byte[]]$Rcvbytes = 0..4096 | ForEach-Object {0xFF}
[Int]$PacketDelay = 500
$data = $datastring = $NULL
[Int]$CDRCounter = 0
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
Check-OXE

# Init Connection
$Client = New-Object System.Net.Sockets.TCPClient($OXEMain,$TicketPort)
$Stream = $Client.GetStream()
$Client.ReceiveTimeout = 31000;

#
# Preamble
#
#Write-Host "Init Phase"
$timestamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")  | Out-File -FilePath $LogFile 
$Stream.Write($InitMessage,0,$InitMessage.Length)
$MsgCounter++
#Start-Sleep -m $PacketDelay
$i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
#$i | Format-Hex | Out-File   -FilePath $LogFile -Append
$data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes,0, $i)
$datastring = [System.BitConverter]::ToString($data)  

#Write-Host "$MsgCounter. Received $($data.Length) bytes : $datastring"

switch ($data.Length)
    {
        2 {
#            Write-Host -NoNewLine "Got 2 bytes "
            if ($datastring -eq $StartMsg)
                {
                Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
                $i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)
                $data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes,0, $i)
                $datastring = [System.BitConverter]::ToString($data)
#                Write-Host "$MsgCounter. Received $($data.Length) bytes : $datastring"
                            if ($datastring -eq "50")
                            {
                            Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
                            }

                }
            }
        3 {
            if ($datastring -eq $ThreeBytesAnswer)
                {
                Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
                Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
                                }
            }
        5 {
            if ($datastring -eq $FiveBytesAnswer)
                {
                Write-Host -ForegroundColor Yellow "Start sequence reply received, waiting for role..."
                Write-Host -ForegroundColor Yellow "Role is Main. Link Established`n"
                Write-Host -ForegroundColor Yellow "Getting ticket."
                }
            }

        default { exit $ErrorBytes }
    }
$Stream.Write($StartMessage,0,$StartMessage.Length)
$MsgCounter++
$TestKeepAlive = [System.Diagnostics.Stopwatch]::StartNew()
while(($i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)) -ne 0)
{
Write-Host -ForegroundColor Yellow "--- Wait for tickets" $CDRCounter "/" $MAOCounter "/" $VOIPCounter 
$data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes,0, $i)
$data | Format-Hex | Out-File   -FilePath $LogFile -Append

switch ($data.Length) {
    1 
      {
         Write-Host "Unknown command. Check logs."
         $datastring = [System.BitConverter]::ToString($data)
      }
    2 
      {
        $datastring = [System.BitConverter]::ToString($data) 
      }
    3 
      {
        $datastring = [System.BitConverter]::ToString($data) 
      }
    5 
      {
        $datastring = [System.BitConverter]::ToString($data)
      }
    8 
      {
        $datastring = [System.Text.Encoding]::UTF8.GetString($data)
      }

# Single accounting ticket is of fixed size 772 bytes
# Actually less (528) the rest is padded with "00"
# MAO ticket is variable size but "packet" is still 772 bytes
# 
    $TicketMessageLength 
      {
          $ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
          if ($TicketReady)
            {
              $TicketFlag = [System.BitConverter]::ToString($data[0..3])
               Write-Host -NoNewline "Ticket Flag is " $TicketFlag " "
             switch ($TicketFlag)
               {
                 $EmptyTicket
                   {
                     Write-Host "Empty Ticket"
                   }
                 $MAOTicket
                   {
                   Write-Host "MAO Ticket"
                   $MAOdata = $ProcessTicket.Substring(4, $ProcessTicket.IndexOf(0x0a) -4)  -replace ("=", "`t") -replace ".{1}$" -Split ";"
                   
                   Foreach ($MAOLine in $MAOdata)
                     {
                       $MAOField = $MAOLine.Split("`t")
                       Write-Host $MAOfield[0] $MAOField[1] ":" $MAOField.Count 
                     }
                     $MAOCounter++ 
                 }
               $NormalTicket
                 {
                   Write-Host "SMDR Ticket.The length is "  $ProcessTicket.Length
                   $TicketForm = @(
                   $TicketFields | Select-Object | ForEach-Object {
                   $ProcessTicket.Remove($_)
                   $ProcessTicket = $ProcessTicket.Substring($_)
                   }
                   )
                   $CDRCounter++                       
                   for ($f = 2; $f -lt $TicketForm.Length; $f++)
                     {
                        Write-Host  $FieldsNames[$f]":" $TicketForm[$f].Trim()
                     }

                 }
                
               default
                 {
                   Write-Host "Unknown ticket type. Check logs."
                 }

             }
}
# After ticket is processed modify $datastring so its not command again.
           $TicketReady = $false
           $datastring = "Ticket Info"
           
}

# Buffer processing
#
    default {
              $datastring = [System.Text.Encoding]::ASCII.GetString($data)
              $BufferBuffer = $data
              Write-Host "Read buffer:" $BufferBuffer.Length
if ( $TicketTruncated )
     {
       $BufferBuffer = $TruncPart1 + $data
       Write-Host "Appended data left from previous packets."
       $TicketTruncated = $false
     }
$StartPointer = 0    

While ( $StartPointer -lt $BufferBuffer.Length )
  {
 $datastring = [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + 1)]) 
switch ( $datastring )
    {
    $TicketInfo
      {
        Write-Host "Continue buffer processing ..."
        $TicketReady = $true

        $StartPointer++
        $StartPointer++
      }
    $TicketMark
      {
        Write-Host "Start buffer processing.."
      }
    default
      {
        Write-Host "Wrong data...Check logs."
      }
   }

#
# Load one ticket record into $data variable
$data = $BufferBuffer[$StartPointer..($StartPointer + $TicketMessageLength)]
#
# convert this record to ASCII
$ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
Write-Host "Buffer Pointer:" $StartPointer "/" $BufferBuffer.Length
$LeftToProcess = $BufferBuffer.Length - $StartPointer 

if ( $LeftToProcess -lt $TicketMessageLength )
  {
    Write-Host "Bytes left :" $LeftToProcess ". Next ticket is truncated."
    $TicketTruncated = $true
    $TruncPart1 = $data
  }
# If ($TicketReady)
  
           $TicketFlag = [System.BitConverter]::ToString($ProcessTicket[0..3])
           Write-Host -NoNewline "Ticket Flag is " $TicketFlag " "
           switch ($TicketFlag)
             {
               $EmptyTicket
                 {
                   Write-Host "Empty Ticket"
                 }
               $MAOTicket
                 {
                   Write-Host "MAO Ticket"
                   $MAOdata = $ProcessTicket.Substring(4, $ProcessTicket.IndexOf(0x0a) -4)  -replace ("=", "`t") -replace ".{1}$" -Split ";"
                   Foreach ($MAOLine in $MAOdata)
                     {
                       $MAOField = $MAOLine.Split("`t")
                       Write-Host $MAOfield[0] $MAOField[1] ":" $MAOField.Count 
                     }
                   $MAOCounter++ 
                 }
               $NormalTicket
                 {
                   if ( -Not ($TicketTruncated) )
                     {
                       Write-Host "SMDR Ticket. The length is "  $ProcessTicket.Length
                       $CDRCounter++
                       $TicketReady = $false

                       $TicketForm = @(
                       $TicketFields | Select-Object | ForEach-Object {
                       $ProcessTicket.Remove($_)
                       $ProcessTicket = $ProcessTicket.Substring($_)
                       }
                   )
                   Write-Host "--- Ticket " $CDRCounter ":"

                    for ($f = 2; $f -lt $TicketForm.Length; $f++)
                     {
                        Write-Host  $FieldsNames[$f]":" $TicketForm[$f].Trim()
                     }
                      }
                      else 
                        {
                          Write-Host " Waiting for the rest of ticket..."
                        }
                }
                
               default
                 {
                   Write-Host "Unknown ticket type. Check logs."
                 }

             }
           
$StartPointer = $StartPointer + $TicketMessageLength


  Write-Host "Buffer processing.. $CDRCounter tickets processed "
  }
#  Write-Host $StartPointer "vs" $BufferBuffer.Length
# Проверка на длину буфера закрывающая скобка
#        }
                     $datastring = "Ticket Info"
        
        }
    }

Write-Host -NoNewLine "$MsgCounter. Received $($data.Length) bytes:" 
# $datastring  

switch ($datastring)
    {
        "03-04" 
          {
            Write-Host "Ticket Ready Command"
            $TicketReady = $true
          }
        "00-08"
          {
            Write-Host "Test Request Command"
            $KeepAliveReq = $true
            $Stream.Write($TestReply,0,$TestReply.Length)
            $MsgCounter++
          }
        "TEST_REQ"
          {
            Write-Host "Test Request String"
            if ($KeepAliveReq)
              {
#            $Stream.Write($TestReply,0,$TestReply.Length)
#            $KeepAliveReq = $false
              Start-Sleep -m $PacketDelay
              $Stream.Write($TestMessage,0,$TestMessage.Length)
              $MsgCounter++
              Write-Host "$MsgCounter. Reply with TEST_RSP"
              Write-Host -ForegroundColor Green "--- Running for" $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss')
              }
          }
         "Ticket Info"
            {
              Write-Host "Ticket Information"
            }
        default
          {
            if ($datastring.Length -lt 772)
              {
                Write-Host -ForegroundColor Red "Unknown command :" $datastring.Length  "-"  $datastring "Log written."
                $datastring | Format-Hex | Out-File   -FilePath $LogFile -Append
              }
            else
              {
                Write-Host "Buffer processing.."

              }
          }
    }


$MsgCounter++

}

#
# Main body
#
if ( -Not (Get-NetTCPConnection -State Established -RemotePort $TicketPort -ErrorAction SilentlyContinue) )
    {
    Write-Host "Connection closed from server."
    }
Write-Host "Disconnect." "Uptime: " $TestKeepAlive.Elapsed.ToString('dd\.hh\:mm\:ss') "Tickets received :" $CDRCounter
$Stream.Flush()
$Client.Close()