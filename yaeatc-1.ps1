# version 1.3
Param(
#    [Parameter(Mandatory)]
    $OXEMain = "192.168.92.52",
    $TicketPort = 2533
)

# Working Directory
$EACCFolder = "C:\Temp\EACC\"
# Log file
$LogFile = $EACCFolder + "log.txt"

$TicketFields = @(4,5,30,30,20,10,16,5,20,30,2,1,17,5,10,10,5,5,5,1,16,7,1,2,10,5,40,40,10,10,10,10,1,2,2,2,30,5,10,1,17,30,5,5,5,5,5,6,6)
$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$EmptyTicket = "01-00-01-00"
$NormalTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$TcktVersion = "ED5.2"
$FieldsCounter = 1


function Check-OXE
{
    Write-Host  -NoNewline "Host $OXEMain is reachable : "
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
$TicketInfo = "03-04"
$ThreeBytesAnswer = $StartMsg + "-" + $MainCPU
$FiveBytesAnswer = $ThreeBytesAnswer + "-" + $TicketInfo
$ACKMessageStr = "03-04"
$TestRequest = "TEST_REQ"
[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02,0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x08
[Byte[]]$TestMessage = 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
[byte[]]$Rcvbytes = 0..1024 | ForEach-Object {0xFF}
[Int]$PacketDelay = 500
$data = $datastring = $NULL
[Int]$TicketCounter = 0
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

Write-Host $FieldsNames.Length  "fields in 5.2 version"
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
Write-Host -ForegroundColor Yellow "--- Wait for tickets ($TicketCounter)"
$data = (New-Object -TypeName System.Text.ASCIIEncoding).Getbytes($Rcvbytes,0, $i)
$data | Format-Hex | Out-File   -FilePath $LogFile -Append

switch ($data.Length) {
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
    772 {
#        $datastring = [System.Text.Encoding]::ASCII.GetString($data)
#        $ProcessTicket = $datastring
        $ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
        if ($TicketReady)
          {
           $TicketFlag = [System.BitConverter]::ToString($data[0..3])
           Write-Host -NoNewline "Ticket Flag is " $TicketFlag " "
#           $TicketReady = $false
           switch ($TicketFlag)
             {
               $EmptyTicket
                 {
                   Write-Host "Empty Ticket"
                 }
               $MAOTicket
                 {
                   Write-Host "MAO Ticket"
                   $MAOdata = $ProcessTicket.Substring(4, $ProcessTicket.IndexOf(0x0a) -4) -Split ";" -replace ("=", "`t")
                   Write-Host $MAOdata | Format-List
#                   $MAOdata.Substring(4, $MAOdata.IndexOf(0x0a) -4) -split ";"

                 }
               $NormalTicket
                 {
                   Write-Host "SMDR Ticket"
                   
            $TicketForm = @(
            $TicketFields | Select-Object | ForEach-Object {
            $ProcessTicket.Remove($_)
            $ProcessTicket = $ProcessTicket.Substring($_)
            }
            )

$f = 0
$TicketCounter++                       
ForEach ($Field in $TicketForm)
  {
    Write-Host  $f $Field ":"$Field.Length
    $f++
  }




                 }
                
               default
                 {
                   Write-Host "Unknown ticket type. Check logs."
                 }

             }
         <#
         $TicketReady = $false
         $TicketForm = @(
         $TicketFields | Select-Object | ForEach-Object 
            {
             $ProcessTicket.Remove($_)
             $ProcessTicket = $ProcessTicket.Substring($_)
             }
                        )
                        #>
#            Write-Host "Ticket Information:" $TicketForm.Length "fields processed"
<#
            $i = 0
    if ( $TicketForm[1] -ne $TcktVersion )
        {
            Write-Host "Empty ticket received."
        }
    
    else 
    {
     $TicketCounter++

    ForEach ($Field in $TicketForm)
    {
#        $FieldHex = [System.BitConverter]::ToString($Field)
#       $FieldHex = [System.Text.Encoding]::OEM.GetString($Field)
#       $FieldHex = [System.BitConverter]::ToString($Field)
        Write-Host  $i $Field ":"$Field.Length
        $i++
    }
            }
        }
#    $TicketFlag = $datastring = [System.BitConverter]::ToString($data[0..3])
#        Write-Host "Ticket Flag is " $TicketFlag
#        $datastring = $TicketFlag
    }
#>
}
           $TicketReady = $false
           
}

    default {
        $datastring = [System.Text.Encoding]::ASCII.GetString($data)
        }
    }

Write-Host -NoNewLine "$MsgCounter. Received $($data.Length) bytes." 
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
        default
          {
            if ($datastring.Length -lt 772)
              {
                Write-Host -ForegroundColor Red "Unknown command :" $datastring.Length  "-"  $datastring "Log written."
                $datastring | Format-Hex | Out-File   -FilePath $LogFile -Append
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
Write-Host "Disconnect." $TestKeepAlive.Elapsed.TotalSeconds "Tickets received " $TicketCounter
$Stream.Flush()
$Client.Close()