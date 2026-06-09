# ============================================================
#  Launch-ClaudeCode.ps1  v9
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function ToInvStr([double]$v){ return $v.ToString([cultureinfo]::InvariantCulture) }

# ---- History -----------------------------------------------
$Global:HistFile = Join-Path $env:APPDATA "ClaudeCodeLauncher\history.txt"
function Load-History {
    if(Test-Path $Global:HistFile){
        return @(Get-Content $Global:HistFile -Encoding UTF8 |
            Where-Object{$_.Trim()-ne''} | Select-Object -First 10)
    }
    return @()
}
function Save-History([string]$p){
    $f=Split-Path $Global:HistFile -Parent
    if(-not(Test-Path $f)){New-Item -ItemType Directory -Path $f|Out-Null}
    $old=Load-History|Where-Object{$_-ne$p}
    @($p)+$old|Select-Object -First 10|Set-Content $Global:HistFile -Encoding UTF8
}

# ---- Find claude -------------------------------------------
function Find-Claude {
    $c=@(
        "$env:USERPROFILE\.local\bin\claude.cmd",
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:LOCALAPPDATA\Programs\claude\claude.exe",
        "$env:APPDATA\npm\claude.cmd",
        "$env:APPDATA\npm\claude.exe"
    )
    foreach($x in $c){if(Test-Path $x){return $x}}
    $p=Get-Command claude -ErrorAction SilentlyContinue
    if($p){return $p.Source}
    return $null
}

# ---- Colors ------------------------------------------------
$G_BG    =[System.Drawing.Color]::FromArgb(255,24,24,24)
$G_PANEL =[System.Drawing.Color]::FromArgb(255,34,34,34)
$G_INNER =[System.Drawing.Color]::FromArgb(255,20,20,20)
$G_INPUT =[System.Drawing.Color]::FromArgb(255,50,50,50)
$G_TEXT  =[System.Drawing.Color]::FromArgb(255,220,220,220)
$G_DIM   =[System.Drawing.Color]::FromArgb(255,130,130,130)
$G_ACC   =[System.Drawing.Color]::FromArgb(255,204,120,54)
$G_BTN   =[System.Drawing.Color]::FromArgb(255,58,58,58)
$G_RED   =[System.Drawing.Color]::FromArgb(255,160,50,50)
$G_GREEN =[System.Drawing.Color]::FromArgb(255,50,160,90)

# ---- UI helpers --------------------------------------------
function MkLbl($t,$x,$y,$bold=$false,$col=$null){
    $l=New-Object System.Windows.Forms.Label
    $l.Text=$t;$l.AutoSize=$true
    $l.Location=New-Object System.Drawing.Point($x,$y)
    $l.BackColor=[System.Drawing.Color]::Transparent
    $l.ForeColor=if($col){$col}else{$G_DIM}
    if($bold){$l.Font=New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)}
    return $l
}
function MkTxt($x,$y,$w,$text=''){
    $t=New-Object System.Windows.Forms.TextBox
    $t.Size=New-Object System.Drawing.Size($w,26)
    $t.Location=New-Object System.Drawing.Point($x,$y)
    $t.BackColor=$G_INPUT;$t.ForeColor=$G_TEXT
    $t.BorderStyle='FixedSingle';$t.Text=$text
    return $t
}
function MkBtn($t,$x,$y,$w=80,$h=28,$col=$null){
    $b=New-Object System.Windows.Forms.Button
    $b.Text=$t;$b.Size=New-Object System.Drawing.Size($w,$h)
    $b.Location=New-Object System.Drawing.Point($x,$y)
    $b.BackColor=if($col){$col}else{$G_BTN}
    $b.ForeColor=$G_TEXT;$b.FlatStyle='Flat'
    $b.FlatAppearance.BorderSize=0
    return $b
}
function BrowseFolder($start){
    $d=New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description="Select directory"
    $d.SelectedPath=if($start-and(Test-Path $start)){$start}else{$env:USERPROFILE}
    if($d.ShowDialog()-eq"OK"){return $d.SelectedPath}
    return $null
}

# ---- Global state ------------------------------------------
$Global:LastDir  = ''
$Global:PaneBoxes= @()
$Global:M3Boxes  = @()
$Global:M3Pool   = [System.Collections.Generic.List[string]]::new()
$Global:M3LstBox = $null
$Global:LogLines = [System.Collections.Generic.List[string]]::new()
$Global:LogBox   = $null

function Write-Log([string]$msg){
    $ts=[datetime]::Now.ToString('HH:mm:ss')
    $line="[$ts] $msg"
    $Global:LogLines.Add($line)
    if($Global:LogBox -ne $null -and -not $Global:LogBox.IsDisposed){
        try{
            $Global:LogBox.AppendText($line+"`n")
            $Global:LogBox.ScrollToCaret()
        }catch{}
    }
}

function AddToPool([string]$p){
    $p=$p.Trim()
    if($p-eq''){return}
    if(-not $Global:M3Pool.Contains($p)){
        $Global:M3Pool.Add($p)
        if($Global:M3LstBox-ne$null){$Global:M3LstBox.Items.Add($p)|Out-Null}
        Write-Log "Pool: added $p"
    }
}

# ===========================================================
# BUILD MODE PANELS
# ===========================================================

# ---- Mode 1: same dir for all panes ------------------------
function Build-Mode1([System.Windows.Forms.Panel]$pnl){
    $pnl.Controls.Clear()
    $pnl.AutoScroll=$false

    # Top strip: label + textbox + buttons, fixed height
    $top=New-Object System.Windows.Forms.Panel
    $top.Dock='Top'
    $top.Height=100
    $top.BackColor=$G_PANEL
    $pnl.Controls.Add($top)

    $top.Controls.Add((MkLbl 'Working Directory:' 12 10 $true $G_TEXT))

    $tb=New-Object System.Windows.Forms.TextBox
    $tb.Name='M1_TXT'
    $tb.Location=New-Object System.Drawing.Point(12,30)
    $tb.Size=New-Object System.Drawing.Size(1,26)   # width set by Resize
    $tb.Anchor='Top,Left,Right'
    $tb.BackColor=$G_INPUT;$tb.ForeColor=$G_TEXT
    $tb.BorderStyle='FixedSingle';$tb.Text=$Global:LastDir
    $top.Controls.Add($tb)

    $bBr=MkBtn 'Browse...' 10 30 88
    $bBr.Anchor='Top,Right'
    $bBr.Add_Click({
        $r=BrowseFolder $tb.Text
        if($r){$tb.Text=$r;Write-Log "Mode1 browse: $r"}
    }.GetNewClosure())
    $top.Controls.Add($bBr)

    $bPa=MkBtn 'Paste' 10 30 60
    $bPa.Anchor='Top,Right'
    $bPa.Add_Click({
        $v=[System.Windows.Forms.Clipboard]::GetText().Trim()
        $tb.Text=$v;Write-Log "Mode1 paste: $v"
    }.GetNewClosure())
    $top.Controls.Add($bPa)

    $top.Controls.Add((MkLbl 'Recent Directories  (click to select):' 12 68 $false $G_DIM))

    # Resize handler to keep textbox width and button positions correct
    $top.Add_Resize({
        $tb.Width = $top.Width - 88 - 60 - 36
        $bBr.Left  = $top.Width - 88 - 60 - 8
        $bPa.Left  = $top.Width - 60 - 4
    }.GetNewClosure())

    # Bottom fill: recent dirs listbox
    $lst=New-Object System.Windows.Forms.ListBox
    $lst.Name='M1_LST'
    $lst.Dock='Fill'
    $lst.BackColor=$G_INNER;$lst.ForeColor=$G_TEXT
    $lst.BorderStyle="FixedSingle"
    $lst.Font=New-Object System.Drawing.Font('Consolas',9)
    $hist=Load-History
    if($hist.Count-eq 0){
        $lst.Items.Add("No recent directories yet")|Out-Null
        $lst.Enabled=$false
    }else{
        foreach($h in $hist){$lst.Items.Add($h)|Out-Null}
        $lst.SelectedIndex=0
    }
    $lst.Add_Click({
        if($lst.SelectedItem -and $lst.Enabled){
            $tb.Text=$lst.SelectedItem.ToString()
            Write-Log "Mode1 recent: $($lst.SelectedItem)"
        }
    }.GetNewClosure())
    $lst.Add_DoubleClick({
        if($lst.SelectedItem -and $lst.Enabled){
            $tb.Text=$lst.SelectedItem.ToString()
        }
    }.GetNewClosure())
    $pnl.Controls.Add($lst)
}

# ---- Mode 2: custom dir per pane ---------------------------
function Build-Mode2([System.Windows.Forms.Panel]$pnl,[int]$n){
    $pnl.Controls.Clear()
    $Global:PaneBoxes=@()
    $pnl.AutoScroll=$false

    # Header label docked top
    $hdr=New-Object System.Windows.Forms.Panel
    $hdr.Dock='Top'
    $hdr.Height=28
    $hdr.BackColor=$G_PANEL
    $hdr.Controls.Add((MkLbl "Custom directory for each of $n panes:" 8 6 $true $G_TEXT))
    $pnl.Controls.Add($hdr)

    # Scrollable inner panel docked Fill
    $sc=New-Object System.Windows.Forms.Panel
    $sc.Dock='Fill'
    $sc.AutoScroll=$true
    $sc.BackColor=$G_PANEL
    $pnl.Controls.Add($sc)

    for($i=0;$i -lt $n;$i++){
        $y=$i*38

        $lbl=MkLbl "Pane $($i+1):" 4 ($y+8) $true $G_ACC
        $sc.Controls.Add($lbl)

        $tb=New-Object System.Windows.Forms.TextBox
        $tb.Name="M2_TXT_$i"
        $tb.Location=New-Object System.Drawing.Point(72,($y+4))
        $tb.Size=New-Object System.Drawing.Size(1,26)
        $tb.Anchor='Top,Left,Right'
        $tb.BackColor=$G_INPUT;$tb.ForeColor=$G_TEXT
        $tb.BorderStyle='FixedSingle';$tb.Text=$Global:LastDir
        $sc.Controls.Add($tb)
        $Global:PaneBoxes+=$tb

        $ii=$i

        $bBr=MkBtn '...' 10 ($y+4) 32
        $bBr.Anchor='Top,Right'
        $bBr.Name="M2_BR_$i"
        $bBr.Add_Click({
            $box=$Global:PaneBoxes[$ii]
            $r=BrowseFolder $box.Text
            if($r){$box.Text=$r;Write-Log "Mode2 pane $($ii+1) browse: $r"}
        }.GetNewClosure())
        $sc.Controls.Add($bBr)

        $bPa=MkBtn 'Paste' 10 ($y+4) 58
        $bPa.Anchor='Top,Right'
        $bPa.Name="M2_PA_$i"
        $bPa.Add_Click({
            $v=[System.Windows.Forms.Clipboard]::GetText().Trim()
            $Global:PaneBoxes[$ii].Text=$v
            Write-Log "Mode2 pane $($ii+1) paste: $v"
        }.GetNewClosure())
        $sc.Controls.Add($bPa)
    }

    # Fix textbox widths and button positions on resize
    $sc.Add_Resize({
        $w=$sc.ClientSize.Width
        for($i=0;$i -lt $Global:PaneBoxes.Count;$i++){
            $Global:PaneBoxes[$i].Width = $w - 72 - 32 - 58 - 16
            # reposition Browse and Paste buttons
            $br=$sc.Controls["M2_BR_$i"]
            $pa=$sc.Controls["M2_PA_$i"]
            if($br){$br.Left=$w - 32 - 58 - 8}
            if($pa){$pa.Left=$w - 58 - 4}
        }
    }.GetNewClosure())
}

# ---- Mode 3: assign dirs to panes --------------------------
function Build-Mode3([System.Windows.Forms.Panel]$pnl,[int]$n){
    $pnl.Controls.Clear()
    $Global:M3Boxes=@()
    $Global:M3Pool.Clear()
    $Global:M3LstBox=$null
    $pnl.AutoScroll=$false

    # Left panel docked Left - fixed 230px wide
    $left=New-Object System.Windows.Forms.Panel
    $left.Dock='Left'
    $left.Width=230
    $left.BackColor=$G_PANEL
    $pnl.Controls.Add($left)

    $left.Controls.Add((MkLbl 'Directory Pool:' 10 10 $true $G_TEXT))

    $lst=New-Object System.Windows.Forms.ListBox
    $lst.Name='M3_LST'
    $lst.Location=New-Object System.Drawing.Point(10,30)
    $lst.Size=New-Object System.Drawing.Size(210,1)   # height set by Resize
    $lst.Anchor='Top,Left,Right,Bottom'
    $lst.BackColor=$G_INNER;$lst.ForeColor=$G_TEXT
    $lst.BorderStyle="FixedSingle"
    $lst.Font=New-Object System.Drawing.Font('Consolas',8)
    $left.Controls.Add($lst)
    $Global:M3LstBox=$lst

    $bAdd=MkBtn '+ Browse & Add' 10 10 134 26
    $bAdd.Anchor='Bottom,Left'
    $bAdd.Add_Click({
        $r=BrowseFolder $Global:LastDir
        if($r){AddToPool $r;Write-Log "Mode3 pool add: $r"}
    })
    $left.Controls.Add($bAdd)

    $bRem=MkBtn '- Remove' 152 10 68 26 $G_RED
    $bRem.Anchor='Bottom,Left'
    $bRem.Add_Click({
        $s=$Global:M3LstBox.SelectedItem
        if($s){
            $Global:M3Pool.Remove($s)|Out-Null
            $Global:M3LstBox.Items.Remove($s)
            Write-Log "Mode3 pool remove: $s"
        }
    })
    $left.Controls.Add($bRem)

    $bAll=MkBtn 'Assign selected to ALL panes' 10 10 210 26
    $bAll.Anchor='Bottom,Left'
    $bAll.ForeColor=$G_ACC
    $bAll.Add_Click({
        $s=$Global:M3LstBox.SelectedItem
        if($s){
            foreach($b in $Global:M3Boxes){$b.Text=$s.ToString()}
            Write-Log "Mode3 assign all: $s"
        }
    })
    $left.Controls.Add($bAll)

    # Resize left panel to set listbox height and button positions
    $left.Add_Resize({
        $h=$left.Height
        $lst.Height = $h - 30 - 26 - 26 - 26 - 16
        $bAdd.Top  = $h - 26 - 26 - 26 - 6
        $bRem.Top  = $h - 26 - 26 - 26 - 6
        $bAll.Top  = $h - 26 - 26 - 6
        # bottom-most button
        $bAll.Top  = $h - 26 - 4
        $bAdd.Top  = $h - 56 - 4
        $bRem.Top  = $h - 56 - 4
        $lst.Height= $h - 30 - 62 - 12
    }.GetNewClosure())

    # Right panel - fill remaining space, with header and scrollable panes
    $right=New-Object System.Windows.Forms.Panel
    $right.Dock='Fill'
    $right.BackColor=$G_PANEL
    $pnl.Controls.Add($right)

    $rhdr=New-Object System.Windows.Forms.Panel
    $rhdr.Dock='Top'
    $rhdr.Height=26
    $rhdr.BackColor=$G_PANEL
    $rhdr.Controls.Add((MkLbl 'Directory for each pane:' 6 6 $true $G_TEXT))
    $right.Controls.Add($rhdr)

    # Scrollable panel for pane rows
    $sc=New-Object System.Windows.Forms.Panel
    $sc.Dock='Fill'
    $sc.AutoScroll=$true
    $sc.BackColor=$G_PANEL
    $right.Controls.Add($sc)

    for($i=0;$i -lt $n;$i++){
        $y=$i*66

        $sc.Controls.Add((MkLbl "Pane $($i+1)" 4 $y $true $G_ACC))

        $tb=New-Object System.Windows.Forms.TextBox
        $tb.Name="M3_TXT_$i"
        $tb.Location=New-Object System.Drawing.Point(4,($y+18))
        $tb.Size=New-Object System.Drawing.Size(1,24)
        $tb.Anchor='Top,Left,Right'
        $tb.BackColor=$G_INPUT;$tb.ForeColor=$G_TEXT
        $tb.BorderStyle='FixedSingle';$tb.Text=$Global:LastDir
        $sc.Controls.Add($tb)
        $Global:M3Boxes+=$tb

        $ii=$i

        $tb.Add_Leave({
            $v=$Global:M3Boxes[$ii].Text.Trim()
            if($v-ne''){AddToPool $v}
        }.GetNewClosure())

        $bBr=MkBtn 'Browse' 4 ($y+46) 70 22
        $bBr.Add_Click({
            $r=BrowseFolder $Global:M3Boxes[$ii].Text
            if($r){$Global:M3Boxes[$ii].Text=$r;AddToPool $r;Write-Log "Mode3 pane $($ii+1) browse: $r"}
        }.GetNewClosure())
        $sc.Controls.Add($bBr)

        $bPa=MkBtn 'Paste' 80 ($y+46) 62 22
        $bPa.Add_Click({
            $v=[System.Windows.Forms.Clipboard]::GetText().Trim()
            $Global:M3Boxes[$ii].Text=$v
            if($v-ne''){AddToPool $v}
            Write-Log "Mode3 pane $($ii+1) paste: $v"
        }.GetNewClosure())
        $sc.Controls.Add($bPa)

        $bUs=MkBtn 'Use Selected' 148 ($y+46) 110 22
        $bUs.ForeColor=$G_ACC
        $bUs.Add_Click({
            $s=$Global:M3LstBox.SelectedItem
            if($s){$Global:M3Boxes[$ii].Text=$s.ToString();Write-Log "Mode3 pane $($ii+1) use: $s"}
        }.GetNewClosure())
        $sc.Controls.Add($bUs)
    }

    # Fix textbox widths on resize
    $sc.Add_Resize({
        $w=$sc.ClientSize.Width - 8
        foreach($b in $Global:M3Boxes){ $b.Width=$w }
    }.GetNewClosure())

    AddToPool $Global:LastDir
}

# ===========================================================
# MAIN FORM  –  layout: TableLayoutPanel drives everything
# ===========================================================
$Global:LastDir=(Load-History|Select-Object -First 1)
if(-not $Global:LastDir){$Global:LastDir=$env:USERPROFILE}

$form=New-Object System.Windows.Forms.Form
$form.Text="Claude Code Launcher"
$form.Size=New-Object System.Drawing.Size(630,740)
$form.MinimumSize=New-Object System.Drawing.Size(500,500)
$form.StartPosition="CenterScreen"
$form.FormBorderStyle="Sizable"
$form.MaximizeBox=$true
$form.TopMost=$false
$form.BackColor=$G_BG

# ---- Header panel (fixed height 178) -----------------------
$header=New-Object System.Windows.Forms.Panel
$header.Dock='Top'
$header.Height=178
$header.BackColor=$G_BG
$form.Controls.Add($header)

$lbT=MkLbl 'Claude Code Launcher' 14 12 $true $G_ACC
$lbT.Font=New-Object System.Drawing.Font('Segoe UI',14,[System.Drawing.FontStyle]::Bold)
$header.Controls.Add($lbT)

$header.Controls.Add((MkLbl 'Number of panes:' 14 54))
$txtN=MkTxt 150 50 60 '4'
$header.Controls.Add($txtN)
$lbLay=MkLbl 'Layout: 2 rows x 2 cols' 222 54 $true $G_ACC
$header.Controls.Add($lbLay)

$header.Controls.Add((MkLbl 'Directory Mode:' 14 90 $true $G_TEXT))
$rdoSame=New-Object System.Windows.Forms.RadioButton
$rdoSame.Text="Same directory for all panes"
$rdoSame.Location=New-Object System.Drawing.Point(14,110)
$rdoSame.AutoSize=$true;$rdoSame.Checked=$true
$rdoSame.ForeColor=$G_TEXT;$rdoSame.BackColor=$G_BG
$header.Controls.Add($rdoSame)

$rdoCust=New-Object System.Windows.Forms.RadioButton
$rdoCust.Text="Custom directory per pane"
$rdoCust.Location=New-Object System.Drawing.Point(14,132)
$rdoCust.AutoSize=$true
$rdoCust.ForeColor=$G_TEXT;$rdoCust.BackColor=$G_BG
$header.Controls.Add($rdoCust)

$rdoAssign=New-Object System.Windows.Forms.RadioButton
$rdoAssign.Text="Assign directories to specific panes"
$rdoAssign.Location=New-Object System.Drawing.Point(14,154)
$rdoAssign.AutoSize=$true
$rdoAssign.ForeColor=$G_TEXT;$rdoAssign.BackColor=$G_BG
$header.Controls.Add($rdoAssign)

# ---- Mode panel (fills remaining space) - must be added FIRST for Fill to work ----
$modePanel=New-Object System.Windows.Forms.Panel
$modePanel.Dock='Fill'
$modePanel.BackColor=$G_PANEL
$form.Controls.Add($modePanel)

# ---- Log panel (fixed height 160, docked bottom, hidden) ---
$logPanel=New-Object System.Windows.Forms.Panel
$logPanel.Dock='Bottom'
$logPanel.Height=160
$logPanel.BackColor=$G_INNER
$logPanel.Visible=$false
$form.Controls.Add($logPanel)

# ---- Bottom button row (fixed height 50, docked bottom) ----
$btnRow=New-Object System.Windows.Forms.Panel
$btnRow.Dock='Bottom'
$btnRow.Height=50
$btnRow.BackColor=$G_BG
$form.Controls.Add($btnRow)

# Log toggle button (left)
$btnLog=MkBtn 'Activity Log' 14 10 120 30
$btnLog.BackColor=$G_BTN
$btnRow.Controls.Add($btnLog)

# Copy Log button (right of btnLog, hidden until log visible)
$btnCopy=MkBtn 'Copy Log' 142 10 90 30
$btnCopy.BackColor=$G_BTN
$btnCopy.Visible=$false
$btnCopy.Add_Click({
    if($Global:LogLines.Count -gt 0){
        [System.Windows.Forms.Clipboard]::SetText($Global:LogLines -join "`r`n")
        $btnCopy.Text='Copied!'
        $timer=New-Object System.Windows.Forms.Timer
        $timer.Interval=1500
        $timer.Add_Tick({$btnCopy.Text='Copy Log';$timer.Stop();$timer.Dispose()})
        $timer.Start()
    }
}.GetNewClosure())
$btnRow.Controls.Add($btnCopy)

# Launch (anchored right)
$btnLaunch=MkBtn 'Launch' 10 10 130 30 $G_ACC
$btnLaunch.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnLaunch.Anchor='Top,Right'
$btnLaunch.DialogResult="OK"
$form.AcceptButton=$btnLaunch
$btnRow.Controls.Add($btnLaunch)

# Cancel (anchored right)
$btnCancel=MkBtn 'Cancel' 10 10 90 30
$btnCancel.Anchor='Top,Right'
$btnCancel.DialogResult="Cancel"
$form.CancelButton=$btnCancel
$btnRow.Controls.Add($btnCancel)

# Position Launch+Cancel correctly once btnRow has a real width
function Update-BtnPositions {
    $btnLaunch.Left = $btnRow.Width - 238
    $btnCancel.Left = $btnRow.Width - 100
}
$btnRow.Add_Resize({ Update-BtnPositions })
$form.Add_Shown({ Update-BtnPositions })

# Log label strip
$logLabel=New-Object System.Windows.Forms.Label
$logLabel.Text='  Activity Log'
$logLabel.Dock='Top'
$logLabel.Height=18
$logLabel.BackColor=[System.Drawing.Color]::FromArgb(255,30,30,30)
$logLabel.ForeColor=$G_DIM
$logLabel.Font=New-Object System.Drawing.Font('Segoe UI',8,[System.Drawing.FontStyle]::Bold)
$logPanel.Controls.Add($logLabel)

$Global:LogBox=New-Object System.Windows.Forms.RichTextBox
$Global:LogBox.Dock='Fill'
$Global:LogBox.BackColor=$G_INNER
$Global:LogBox.ForeColor=$G_DIM
$Global:LogBox.Font=New-Object System.Drawing.Font('Consolas',8)
$Global:LogBox.ReadOnly=$true
$Global:LogBox.BorderStyle='None'
$Global:LogBox.ScrollBars='Vertical'
$logPanel.Controls.Add($Global:LogBox)

# Override Write-Log now that LogBox exists
function Write-Log([string]$msg){
    $ts=[datetime]::Now.ToString('HH:mm:ss')
    $line="[$ts] $msg"
    $Global:LogLines.Add($line)
    if($Global:LogBox -ne $null -and -not $Global:LogBox.IsDisposed){
        try{
            $Global:LogBox.AppendText($line+"`n")
            $Global:LogBox.ScrollToCaret()
        }catch{}
    }
}

# Wire log toggle button now that logPanel exists
$btnLog.Add_Click({
    $logPanel.Visible = -not $logPanel.Visible
    if($logPanel.Visible){
        $btnLog.BackColor=$G_GREEN
        $btnCopy.Visible=$true
    }else{
        $btnLog.BackColor=$G_BTN
        $btnCopy.Visible=$false
    }
}.GetNewClosure())

# Rebuild panel function
function Rebuild-Panel {
    $nv=0
    if(-not([int]::TryParse($txtN.Text,[ref]$nv))-or$nv -lt 1){$nv=1}
    if($rdoSame.Checked)   {Build-Mode1 $modePanel}
    elseif($rdoCust.Checked){Build-Mode2 $modePanel $nv}
    else                    {Build-Mode3 $modePanel $nv}
}

$txtN.Add_TextChanged({
    $nv=0
    if([int]::TryParse($txtN.Text,[ref]$nv)-and$nv-ge 1){
        if($nv-eq 1){$lbLay.Text='Layout: 1 pane'}
        elseif($nv%2-eq 0){$lbLay.Text="Layout: $($nv/2) rows x 2 cols"}
        else{$lbLay.Text="Layout: $([int][math]::Ceiling($nv/2)) rows (top full-width)"}
    }else{$lbLay.Text='Layout: --'}
    Rebuild-Panel
})

$rdoSame.Add_CheckedChanged({if($rdoSame.Checked){Rebuild-Panel}})
$rdoCust.Add_CheckedChanged({if($rdoCust.Checked){Rebuild-Panel}})
$rdoAssign.Add_CheckedChanged({if($rdoAssign.Checked){Rebuild-Panel}})

Build-Mode1 $modePanel

$result=$form.ShowDialog()
if($result -ne 'OK'){exit}

# Collect pane dirs
$nv=0;[int]::TryParse($txtN.Text,[ref]$nv)|Out-Null
if($nv -lt 1){$nv=1}
$paneDirs=@()

if($rdoSame.Checked){
    $d=$modePanel.Controls['M1_TXT'].Text.Trim()
    for($i=0;$i -lt $nv;$i++){$paneDirs+=$d}
}elseif($rdoCust.Checked){
    for($i=0;$i -lt $nv;$i++){
        if($i -lt $Global:PaneBoxes.Count){$paneDirs+=$Global:PaneBoxes[$i].Text.Trim()}
        else{$paneDirs+=$Global:LastDir}
    }
}else{
    for($i=0;$i -lt $nv;$i++){
        if($i -lt $Global:M3Boxes.Count){$paneDirs+=$Global:M3Boxes[$i].Text.Trim()}
        else{$paneDirs+=$Global:LastDir}
    }
}

# Validate
for($i=0;$i -lt $paneDirs.Count;$i++){
    if(-not(Test-Path -LiteralPath $paneDirs[$i] -PathType Container)){
        [System.Windows.Forms.MessageBox]::Show(
            "Pane $($i+1) directory not found:`n$($paneDirs[$i])",'Error','OK','Error')
        exit
    }
}
if(-not(Get-Command wt.exe -ErrorAction SilentlyContinue)){
    [System.Windows.Forms.MessageBox]::Show('Windows Terminal not found.','Error','OK','Error');exit
}
$claudePath=Find-Claude
if(-not $claudePath){
    [System.Windows.Forms.MessageBox]::Show(
        "Claude Code not found.`n`nRun: irm https://claude.ai/install.ps1 | iex",'Error','OK','Error');exit
}

$paneDirs|Select-Object -Unique|ForEach-Object{Save-History $_}

# ---- Build wt args -----------------------------------------
function Get-ClaudeInvocation([string]$cp){
    if($cp -match '\.cmd$'){
        $safe=$cp -replace '"','""'
        return "cmd /c `"`"$safe`"`""
    }else{
        $safe=$cp -replace "'","''"
        return "& '$safe'"
    }
}

function Build-WtArgs([int]$N,[string[]]$dirs,[string]$cc){
    if($N -lt 1){return @()}
    $rc=[System.Collections.Generic.List[int]]::new()
    if($N%2-eq 1){$rc.Add(1);$rem=$N-1}else{$rem=$N}
    while($rem-gt 0){$rc.Add(2);$rem-=2}
    $rows=$rc.Count
    $dbc=New-Object string[] $N
    $vi=0;$xs=$rows;$xo=0
    for($r=0;$r -lt $rows;$r++){
        $dbc[$r]=$dirs[$vi];$vi++
        if($rc[$r]-eq 2){$dbc[$xs+$xo]=$dirs[$vi];$vi++;$xo++}
    }

    $wtArgs=[System.Collections.Generic.List[string]]::new()
    $d0=$dbc[0] -replace '"','""'
    $wtArgs.Add("new-tab --startingDirectory `"$d0`" -- powershell.exe -NoExit -Command `"$cc`"")

    if($N -eq 1){ return $wtArgs[0] }

    $pi=1;$ra=@(0)
    for($k=1;$k -lt $rows;$k++){
        $sz=ToInvStr(($rows-$k)/($rows-$k+1))
        $dk=$dbc[$pi] -replace '"','""'
        $wtArgs.Add("split-pane --horizontal --size $sz --startingDirectory `"$dk`" -- powershell.exe -NoExit -Command `"$cc`"")
        $ra+=$pi;$pi++
    }
    for($r=0;$r -lt $rows;$r++){
        if($rc[$r]-eq 2){
            $wtArgs.Add("focus-pane --target $($ra[$r])")
            $dk=$dbc[$pi] -replace '"','""'
            $wtArgs.Add("split-pane --vertical --size 0.5 --startingDirectory `"$dk`" -- powershell.exe -NoExit -Command `"$cc`"")
            $pi++
        }
    }
    return ($wtArgs -join ' ; ')
}

$cc=Get-ClaudeInvocation $claudePath
$wtArgStr=Build-WtArgs $nv $paneDirs $cc
Start-Process 'wt.exe' -ArgumentList $wtArgStr