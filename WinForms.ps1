# for talking across runspaces.
$sync = [Hashtable]::Synchronized(@{})

# long running task.
$counter = {
  $count = [PowerShell]::Create().AddScript(
  {
    $sync.button.Enabled = $false
    for ($i = 0; $i -le 20; $i++) {
      $sync.label.Text = "Received $i"
      $sync.MyMultiLineTextBox.AppendText("$i Running Script on $(Get-Date) `r`n")
      $sync.MyMultiLineTextBox.Focus() = $True
      $sync.MyMultiLineTextBox.ScrollToCaret()
 #      $sync.textbox.AppendText("`r`n")
      start-sleep -seconds 1
    }
    $sync.button.Enabled = $true
  }
  )

  $runspace = [RunspaceFactory]::CreateRunspace()
  $runspace.ApartmentState = "STA"
  $runspace.ThreadOptions = "ReuseThread"
  $runspace.Open()
  $runspace.SessionStateProxy.SetVariable("sync", $sync)

  $count.Runspace = $runspace
  $count.BeginInvoke()
}

# create the form.
$CDRWindow = New-Object Windows.Forms.Form
$CDRWindow.ClientSize = New-Object Drawing.Size(1000, 300)
$CDRWindow.Text ="CDR output"
$CDRWindow.StartPosition = "CenterScreen"
$CDRWindow.FormBorderStyle = "FixedSingle"
#$CDRWindow.MaximizeBox = $false
$CDRWindow.Topmost = $True

# create the button.
$button = New-Object Windows.Forms.Button
$button.Location = New-Object Drawing.Point(10, 10)
$button.Width =970
$button.Text = "Start Counting"
$button.Add_Click($counter)

# create the label.
$label = New-Object Windows.Forms.Label
$label.Location = New-Object Drawing.Point(10, 280)
$label.Width = 100
$label.Text = 0
$label.AutoSize = $true
$CDRWindow.Controls.Add($Label)


#$MyMultiLineTextBox = New-Object System.Windows.Forms.TextBox 
$MyMultiLineTextBox = New-Object System.Windows.Forms.RichTextBox
#$MyMultiLineTextBox = New-Object System.Windows.Forms.MessagetBox

$MyMultiLineTextBox.Font = New-Object System.Drawing.Font("Lucida Console",14,[System.Drawing.FontStyle]::Regular)
$MyMultiLineTextBox.Multiline = $True
$MyMultiLineTextBox.Width = 980
$MyMultiLineTextBox.Height = 160
$MyMultiLineTextBox.ForeColor = "#FFFFFF"
$MyMultiLineTextBox.ReadOnly = $True
$MyMultiLineTextBox.Scrollbars = "Both"
$MyMultiLineTextBox.location =New-object system.drawing.point(11,30)
$MyMultiLineTextBox.Font = "Lucida ,12"
$CDRWindow.controls.Add($MyMultiLineTextBox)


# add controls to the form.
$sync.button = $button
$sync.label = $label
$sync.MyMultiLineTextBox = $MyMultiLineTextBox
$CDRWindow.Controls.AddRange(@($sync.button, $sync.label, $sync.MyMultiLineTextBox ))

# show the form.
#[Windows.Forms.Application]::Run($CDRWindow)
[void] $CDRWindow.ShowDialog()