$EAFieldsNames = @("TicketLabel", "TicketVersion", "CalledNumber", "ChargedNumber", "ChargedUserName", "ChargedCostCenter", "ChargedCompany", "ChargedPartyNode", "Subaddress", "CallingNumber", "CallType", "CostType", "EndDateTime", "ChargeUnits", "CostInfo", "Duration", "TrunkIdentity", "TrunkGroupIdentity", "TrunkNode", "PersonalOrBusiness", "AccessCode", "SpecificChargeInfo", "BearerCapability", "HighLevelComp", "DataVolume", "UserToUserVolume", "ExternalFacilities", "InternalFacilities", "CallReference", "SegmentsRate1", "SegmentsRate2", "SegmentsRate3", "ComType", "X25IncomingFlowRate", "X25OutgoingFlowRate", "Carrier", "InitialDialledNumber", "WaitingDuration", "EffectiveCallDuration", "RedirectedCallIndicator", "StartDateTime", "ActingExtensionNumber", "CalledNumberNode", "CallingNumberNode", "InitialDialledNumberNode", "ActingExtensionNumberNode", "TransitTrunkGroupIdentity", "NodeTimeOffset", "TimeDlt")
$EATicketFields = @(4, 5, 30, 30, 20, 10, 16, 5, 20, 30, 2, 1, 17, 5, 10, 10, 5, 5, 5, 1, 16, 7, 1, 2, 10, 5, 40, 40, 10, 10, 10, 10, 1, 2, 2, 2, 30, 5, 10, 1, 17, 30, 5, 5, 5, 5, 5, 6, 6)
$EAEmptyTicket = "01-00-01-00"
$EATicketMark = "01-00"
$EATestMark = "00-08"
$EANormalTicket = "01-00-02-00"
$EAMAOTicket = "01-00-06-00"
$EAFlagLength = "0..3"
$EATcktVersion = "ED5.2"
$EANewTicketAvailable = "03-04"
$EACDRCounter = 0
$EATicketForm = @()
$EAStartPointer = 0
# Last byte of message 772-1
$EATicketMessageLength = 772
$EATicketTruncated = $false
$EAKeepAliveReq = $false
$EAIteration = 0

#$TicketReady = $true

# Reading data from file  
#
$EAFilePath = "C:\Temp\EACC\"
$EABufferFile = "binary.txt"
$EAFullPath = $EAFilePath + $EABufferFile
Set-Location $EAFilePath
Write-Host "Changing working folder to" (Get-Location).Path
Write-Host "Reading buffer from" (Get-Item $EABufferFile).FullName 
$EABufferBuffer = Get-Content $EAFullPath -Encoding Byte
Write-Host "Read bytes:" $EABufferBuffer.Length
$EALeftToProcess = $EABufferBuffer.Length
# 
# Done loading data
#
# Buffer processing
#
#
  while ( ( $EAStartPointer -lt $EABufferBuffer.Length ) -and !($EATicketTruncated)) {
    $EAdatastring = [System.BitConverter]::ToString($EABufferBuffer[$EAStartPointer..($EAStartPointer + 1)])
    Write-Host $EAdatastring | FHX
    $EAIteration++
    switch ( $EAdatastring ) {
      $EANewTicketAvailable {
        Write-Host "New ticket info follows ..."
        $EATicketReady = $true
        $EAStartPointer = $EAStartPointer + 2
      }
      $EATicketMark {
        Write-Host "Getting Ticket Info.."
        $EAStartPointer = $EAStartPointer + 2
       }
      $EATestMark {
        Write-Host -ForegroundColor Green "Test Request Command received."
        $EATicketReady = $false
        $EAKeepAliveReq = $true
        $EAStartPointer = $EAStartPointer + 2
      }
      default {
        Write-Host -ForegroundColor Red "Wrong data...Check logs. $EAdatastring Exiting. "
        exit
      }
    }

    $EAdata = $EABufferBuffer[$EAStartPointer..($EAStartPointer + $EATicketMessageLength)]
    #$EAdata | FHX
# !!! Works for ASCII encoding - CDR and MAO tickets, VoIP tickets are binary
    $EAProcessTicket = [System.Text.Encoding]::ASCII.GetString($EAdata)
# !!! Disable as it looks unnecessary 
#    $EALeftToProcess = $EABufferBuffer.Length - $EAStartPointer
    Write-Host "$EAIteration Buffer Pointer:" $EAStartPointer "/" $EALeftToProcess "/" $EABufferBuffer.Length 
<#
     if ( $EALeftToProcess -lt $EATicketMessageLength ) {
        Write-Host "Bytes left :" $EALeftToProcess ". Next ticket is truncated."
        $EATicketTruncated = $true
        $EATruncPart1 = $EAdata
        }
#>
    If ($EATicketReady) {
      $EATicketFlag = [System.BitConverter]::ToString($EAProcessTicket[0..3])
      Write-Host -NoNewline "Ticket Flag is " $EATicketFlag " "
      switch ($EATicketFlag) {
        $EAEmptyTicket {
          Write-Host "Empty Ticket"
          $EATicketReady = $false
          $EAStartPointer = $EAStartPointer + $EATicketMessageLength
        }
        $EAMAOTicket {
          Write-Host "MAO Ticket"
          $EAMAOdata = $EAProcessTicket.Substring(4, $EAProcessTicket.IndexOf(0x0a) - 4) -replace ("=", "`t") -replace ".{1}$" -Split ";"
          Foreach ($EAMAOLine in $EAMAOdata) {
            $EAMAOField = $EAMAOLine.Split("`t")
            Write-Host $EAMAOfield[0] $EAMAOField[1] ":" $EAMAOField.Count 
          } 
          $EATicketReady = $false
          $EAStartPointer = $EAStartPointer + $EATicketMessageLength
        }
        $EANormalTicket {
          Write-Host "SMDR Ticket"
          $EATicketForm = @(
            $EATicketFields | Select-Object | ForEach-Object {
              $EAProcessTicket.Remove($_)
              $EAProcessTicket = $EAProcessTicket.Substring($_)
            }
          )
          Write-Host -ForegroundColor Yellow   "--- Ticket " $EACDRCounter
<#          
          for ($EAf = 2; $EAf -lt $EATicketForm.Length; $EAf++) {
            Write-Host $EAFieldsNames[$EAf]":" $EATicketForm[$EAf]
          }
#>
          $EACDRCounter++
          $EATicketReady = $false
          $EAStartPointer = $EAStartPointer + $EATicketMessageLength


        }
                
        default {
          Write-Host "Unknown ticket type. Check logs."
        }


      }

          $EALeftToProcess = $EABufferBuffer.Length - $EAStartPointer
          Write-Host "Buffer Pointer:" $EAStartPointer "/" $EALeftToProcess "/" $EABufferBuffer.Length 
          if ( $EALeftToProcess -lt $EATicketMessageLength ) {
            Write-Host "$EAIteration Bytes left :" $EALeftToProcess ". Next ticket is truncated."
            $EATicketTruncated = $true
#            $EATruncPart1 = $EABufferBuffer[$EAStartPointer..$EALeftToProcess]
          }
    }
  }
    $EATruncPart1 = $EABufferBuffer[$EAStartPointer..$EABufferBuffer.Length] 
    Write-Host "Done buffer processing. $EACDRCounter tickets processed "
    if ( $EATicketTruncated ) {
      Write-Host "Need more data from the next buffer."
      }

# Need this for debugging
#      Get-Variable EA*



