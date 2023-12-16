$OXEMain = "192.168.92.5"
$TicketPort = "2533"
$TestReq = "TEST_REQ"

#[Console]::TreatControlCAsInput = $True

[Byte[]]$InitMessage = 0x00, 0x01, 0x53
[Byte[]]$StartMessage = 0x00, 0x02,0x00, 0x00
[Byte[]]$ACKMessage = 0x03, 0x04
[Byte[]]$TestReply = 0x00, 0x09,0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50
#[Byte[]]$TestReq = 0x00, 0x08,0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x45, 0x51
[Byte[]]$Rcvbytes = 0..65535|%{0xFF}
[Bool]$EAConnected = $false
#[System.Windows.MessageBox]::Show('Hello')

Write-Host  -NoNewline "Checking connection for " $OXEMain ": "
		if ( Test-Connection $OXEMain -Count 1 -Quiet   )
			{
				Write-Host -ForegroundColor Green "OK" 
			}
        else
            {
                Write-Host -ForegroundColor Red "NOK"
                Write-Host "Exiting. Check network connection."
                exit -1
            } 


$Client = New-Object System.Net.Sockets.TCPClient($OXEMain,$TicketPort)
$Stream = $Client.GetStream()
Write-Host -NoNewline "Connection on" $TicketPort ": "
        if ( $Client.Connected )
        {
        $EAConnected = $true
        Write-Host -ForegroundColor Green "OK" 
        }
     else
        {
        Write-Host -ForegroundColor Red "NOK"
        Write-Host "Exiting. No Ethernet Account activated on $OXEMain."
        exit -2
        }
#
# EthAcc Init Phase
#
Write-Host "Init Phase"
$Stream.Write($InitMessage,0,$InitMessage.Length)
Start-Sleep -m 200
$Stream.Write($StartMessage,0,$StartMessage.Length)

while(($i = $Stream.Read($Rcvbytes, 0, $Rcvbytes.Length)) -ne 0)
{
$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($Rcvbytes,0, $i)
Write-Host "Received" $data.Length "bytes :" $data
if ($data -eq "TEST_REQ")
    {
    Start-Sleep -m 200
    $Stream.Write($TestReply,0,$TestReply.Length)
    Write-Host "Replying with: TEST_RSP"
    }

}

if ( -Not (Get-NetTCPConnection -State Established -RemotePort 2533 -ErrorAction SilentlyContinue) ) 
    {
    Write-Host "Connection closed from server."
    }
Write-Host "Disconnect."
$Stream.Flush()
$Client.Close()