$OXEMain = "192.168.92.52"
# Use Windows Forms for GUI
Add-Type -AssemblyName System.Windows.Forms
# Create New Instance
$CDRWindow = New-Object system.Windows.Forms.Form
# Window Size
$CDRWindow.ClientSize = '1000,200'
# Window Title
$CDRWindow.Text = "CDR output"
$CDRWindow.StartPosition = "CenterScreen"
# Windows Color Scheme
#$CDRWindow.BackColor = "#FF012456"
#$CDRWindow.ForeColor = "#FFFFFF"


$Label = New-Object System.Windows.Forms.Label
$Label.Font = New-object System.Drawing.Font('Lucida',10,[System.Drawing.FontStyle]::Regular)
$Label.Text = "Starting on $env:ComputerName to PBX address: $OXEMain" 
$Label.Location = New-Object System.Drawing.Point(10,10)
#$Label.Font = 
$Label.AutoSize = $true
$CDRWindow.Controls.Add($Label)
#$MyMultiLineTextBox = New-Object System.Windows.Forms.TextBox 
$MyMultiLineTextBox = New-Object System.Windows.Forms.RichTextBox
$MyMultiLineTextBox.Font = New-Object System.Drawing.Font("Lucida Console",14,[System.Drawing.FontStyle]::Bold)
$MyMultiLineTextBox.Multiline = $True
$MyMultiLineTextBox.Width = 980
$MyMultiLineTextBox.Height = 160
$MyMultiLineTextBox.BackColor = "#FF012456"
$MyMultiLineTextBox.ForeColor = "#FFFFFF"
$MyMultiLineTextBox.ReadOnly = $True
$MyMultiLineTextBox.Scrollbars = "Both"

$MyMultiLineTextBox.location = new-object system.drawing.point(10,30)
$MyMultiLineTextBox.Font = "Lucida ,12"
#$MyMultiLineTextBox.AppendText("`nRunning Fix...")
#$MyMultiLineTextBox.AppendText("`nCompleted Successfully.")
$CDRWindow.controls.Add($MyMultiLineTextBox)

<#
$Label2 = New-Object System.Windows.Forms.Label
$Label2.Text = "Last Password Set:"
$Label2.Location  = New-Object System.Drawing.Point(0,40)
$Label2.AutoSize = $true
$CDRWindow.Controls.Add($Label2)


$WindowOutput = New-Object System.Windows.Forms.TextBox
$WindowOutput.Font = New-Object System.Drawing.Font 'Consolas', 10  # or any other monospaced font
$WindowOutput.Multiline  = $true
$WindowOutput.WordWrap   = $true
$WindowOutput.ScrollBars = 'Both'
$WindowOutput.Anchor     = 'Left, Top, Right, Bottom'  # so it can grow/shrink with the form
$WindowOutput.Text = "Check one two three"
#>

#$i = 0
$LineToPrint = "This is line number"
FOR ($i = 1; $i -le 30; $i++)
{
#Write-Host "$LineToPrint $i printed on"   $(Get-Date)
#$Label2.Text = "$LineToPrint $i printed on Get-Date"
$MyMultiLineTextBox.AppendText("$i Running Script...")
$MyMultiLineTextBox.AppendText("`r`n")
#$MyMultiLineTextBox.Select($MyMultiLineTextBox.Text.Length.Update()

#$MyMultiLineTextBox.SelectionStart = $MyMultiLineTextBox.Text.Length
#$MyMultiLineTextBox.Focus() = $True
#$MyMultiLineTextBox.ScrollToCaret()
Start-Sleep 1
#}

#$MyMultiLineTextBox.Refresh()

$CDRWindow.Update()
[void] $CDRWindow.Show()
}
$CDRWindow.Dispose()


