$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$TicketFields = @(4,5,30,30,20,10,16,5,20,30,2,1,17,5,10,10,5,5,5,1,16,7,1,2,10,5,40,40,10,10,10,10,1,2,2,2,30,5,10,1,17,30,5,5,5,5,5,6,6)
$EmptyTicket = "01-00-01-00"
$TicketMark = "01-00"
$TestMark = "00-08"
$NormalTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$FlagLength ="0..3"
$TcktVersion = "ED5.2"
$TicketInfo = "03-04"
$CDRCounter = 0
$TicketForm = @()
$StartPointer = 0
# Last byte of message 772-1
$TicketMessageLength = 772

$TicketReady = $true

# Reading data from file  
#
$FilePath = "C:\Temp\EACC\"
$BufferFile = "binary.txt"
$FullPath = $FilePath + $BufferFile
Set-Location $FilePath
Write-Host "Changing working folder to" (Get-Location).Path
Write-Host "Reading buffer from" (Get-Item $BufferFile).FullName 
$BufferBuffer = Get-Content $FullPath -Encoding Byte
Write-Host "Read bytes:" $BufferBuffer.Length
# 
# Done loading data

if ( $TicketReady ) 
{
  While ( $StartPointer -lt $BufferBuffer.Length )
  {
$datastring = [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + 1)])
Write-Host $datastring | FHX
switch ( $datastring )
  {
    $TicketInfo
      {
        Write-Host "Continue buffer processing ..."
        $TicketReady = $true
        $StartPointer = $StartPointer + 2
      }
    $TicketMark
      {
        Write-Host "Start buffer processing.."
        
      }
    $TestMark {
        Write-Host -ForegroundColor Green "Test Request Command received."
        $StartPointer = $StartPointer + 2
#        [System.BitConverter]::ToString($BufferBuffer[$StartPointer..($StartPointer + 7)])
        $StartPointer = $StartPointer + 8
        $TicketReady = $false
      }
    default
      {
        Write-Host -ForegroundColor Red "Wrong data...Check logs. $datastring "
      }
  }

$data = $BufferBuffer[$StartPointer..($StartPointer + $TicketMessageLength)]
#$data | FHX
$ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)
Write-Host "Buffer Pointer:" $StartPointer "/" ($BufferBuffer.Length - $StartPointer) "/" $BufferBuffer.Length 

If ($TicketReady)
          {
#           $TicketFlag = [System.BitConverter]::ToString($data[0..3])
           $TicketFlag = [System.BitConverter]::ToString($ProcessTicket[0..3])
           Write-Host -NoNewline "Ticket Flag is " $TicketFlag " "
           switch ($TicketFlag)
             {
               $EmptyTicket
                 {
                   Write-Host "Empty Ticket"
                   $TicketReady = $false
                   $StartPointer = $StartPointer + $TicketMessageLength
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
                     $TicketReady = $false
                     $StartPointer = $StartPointer + $TicketMessageLength
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
                    Write-Host -ForegroundColor Yellow   "--- Ticket " $CDRCounter
                    for ($f = 2; $f -lt $TicketForm.Length; $f++) {
                    Write-Host $FieldsNames[$f]":" $TicketForm[$f]
                    }

                    $CDRCounter++
                    $TicketReady = $false
                    $StartPointer = $StartPointer + $TicketMessageLength
                 }
                
               default
                 {
                   Write-Host "Unknown ticket type. Check logs."
                 }

             }
           }
#$StartPointer = $StartPointer + $TicketMessageLength
Write-Host "Done buffer processing. $CDRCounter tickets processed "
}
}
           


