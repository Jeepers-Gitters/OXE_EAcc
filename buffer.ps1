$FieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$TicketFields = @(4,5,30,30,20,10,16,5,20,30,2,1,17,5,10,10,5,5,5,1,16,7,1,2,10,5,40,40,10,10,10,10,1,2,2,2,30,5,10,1,17,30,5,5,5,5,5,6,6)
$EmptyTicket = "01-00-01-00"
$NormalTicket = "01-00-02-00"
$MAOTicket = "01-00-06-00"
$TcktVersion = "ED5.2"

$TicketReady = $true
$FilePath = "C:\Temp\EACC\"
$BufferFile = "binary.txt"
$FullPath = $FilePath + $BufferFile
Set-Location $FilePath
Write-Host "Changing working folder to" (Get-Location).Path
Write-Host "Reading buffer from" (Get-Item $BufferFile).FullName 
$BufferBuffer = Get-Content $FullPath -Encoding Byte
#$BufferBuffer.GetType() | select BaseType
Write-Host "Read bytes:" $BufferBuffer.Length
$data = $BufferBuffer
$ProcessTicket = [System.Text.Encoding]::ASCII.GetString($data)

If ($TicketReady)
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
           }
           


