$datastring = "ED5.2901234567890                  1234                                              Sedova                        1                    5678                           0020231212 04:01:10    0         0        90    0   55    12                00000000 0         0    000000000000000000000000000000000000000000000000000000000000000000000000000000000        18         0         0         01 0 0 0                                  0        90020231212 03:59:401234                              1    1    1    1    0     0     0                                                                                                                                                                                                                                                       "
$TicketFields = @(2,5,30,30,20,10,16,5,20,30,2,1,17,5,10,10,5,5,5,1,16,7,1,2,10,5,40,40,10,10,10,10,1,2,2,2,30,5,10,1,17,30,5,5,5,5,5,6,6)
$FieldsCounter = 1
$substrings = @(
  $Fields | Select -SkipLast 1 | ForEach-Object {
    $datastring.Remove($_)
    $datastring = $datastring.Substring($_)
    $FieldsCounter++
  }
  $string
)

Write-Host $FieldsCounter "fields processed"

$i = 1
ForEach ($Field in $substrings) 
    {
        Write-Host  $i ":" $Field
        $i++
    } 
