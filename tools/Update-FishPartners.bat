<# : batch portion
@echo off
setlocal
set "FP_SELF=%~f0"
set "FP_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath $env:FP_SELF -Raw; Invoke-Expression $s"
set "FP_EXIT=%ERRORLEVEL%"
echo %FP_ARGS% | find /i "/silent" >nul || pause
exit /b %FP_EXIT%
#>

# ---------------------------------------------------------------------------
# Fish & Partners - one-click updater for WoW: Forever
# Double-click to install or update the addon from GitHub.
# Your settings and data (WTF folder) are never touched.
#   /silent   no window output, no questions (used by the auto-update shortcut)
#   /force    reinstall even if you're already up to date
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$Repo   = 'Butker/FishPartners'
$Branch = 'main'
$Addon  = 'FishPartners'
$Silent = ($env:FP_ARGS -match '/silent')
$Force  = ($env:FP_ARGS -match '/force')
$ConfigDir  = Join-Path $env:APPDATA 'FishPartners'
$ConfigFile = Join-Path $ConfigDir 'updater.json'

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Say([string]$text, [string]$color = 'Gray') {
    if (-not $Silent) { Write-Host $text -ForegroundColor $color }
}

function Show-Header {
    if ($Silent) { return }
    Write-Host ''
    Write-Host '  FISH & PARTNERS  ' -ForegroundColor Black -BackgroundColor DarkYellow -NoNewline
    Write-Host '  WEALTH MANAGEMENT  |  UPDATE DESK' -ForegroundColor DarkYellow
    Write-Host ''
}

function Load-Config {
    if (Test-Path -LiteralPath $ConfigFile) {
        try { return (Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json) } catch { }
    }
    return [pscustomobject]@{ wowRoot = $null; autostartAsked = $false }
}

function Save-Config($cfg) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $cfg | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

function Test-WowRoot([string]$root) {
    if (-not $root) { return $false }
    return (Test-Path -LiteralPath (Join-Path $root '_forever_'))
}

# Walk up from any folder the user picked (AddOns, _forever_, ...) to the WoW root
function Resolve-WowRoot([string]$path) {
    if (-not $path) { return $null }
    $cur = $path.Trim().Trim('"').TrimEnd('\')
    while ($cur) {
        if (Test-WowRoot $cur) { return $cur }
        $parent = Split-Path -Path $cur -Parent
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return $null
}

function Find-WowRoot {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                       'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')) {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($p) {
                $p = $p.TrimEnd('\')
                $candidates.Add($p)
                $candidates.Add((Split-Path -Path $p -Parent))
            }
        } catch { }
    }
    $subs = @('World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft',
              'Games\World of Warcraft', 'Blizzard\World of Warcraft', 'Battle.net\World of Warcraft')
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        foreach ($sub in $subs) { $candidates.Add((Join-Path $d.Root $sub)) }
    }
    foreach ($c in $candidates) {
        try { if (Test-WowRoot $c) { return $c } } catch { }
    }
    return $null
}

function Pick-WowRoot {
    if ($Silent) { return $null }
    Say 'I could not find WoW: Forever automatically.' 'Yellow'
    Say 'Pick your "World of Warcraft" folder (the one that contains _forever_).'
    $picked = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select your World of Warcraft folder (the one that contains _forever_)'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $picked = $dlg.SelectedPath }
    } catch { }
    if (-not $picked) { $picked = Read-Host 'Or paste the folder path here' }
    return (Resolve-WowRoot $picked)
}

function Get-TocVersion([string]$text) {
    if ($text -match '(?m)^##\s*Version:\s*([0-9][0-9\.]*)') { return $Matches[1].Trim('.') }
    return $null
}

function Compare-Versions([string]$a, [string]$b) {
    try {
        $va = [version]($a + $(if ($a -notmatch '\.') { '.0' } else { '' }))
        $vb = [version]($b + $(if ($b -notmatch '\.') { '.0' } else { '' }))
        return $va.CompareTo($vb)
    } catch { return [string]::Compare($a, $b) }
}

function Get-ChangelogSection([string]$file, [string]$version) {
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $out = @(); $on = $false
    foreach ($line in (Get-Content -LiteralPath $file)) {
        if ($line -match '^##\s') {
            if ($on) { break }
            if ($line -match [regex]::Escape($version)) { $on = $true; continue }
        } elseif ($on -and $line.Trim()) { $out += $line }
    }
    return $out
}

function Install-Autostart {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = Join-Path $startup 'Fish & Partners updater.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = $env:ComSpec
    $sc.Arguments = '/c ""' + $env:FP_SELF + '" /silent"'
    $sc.WindowStyle = 7
    $sc.Description = 'Checks GitHub for Fish & Partners updates at Windows login'
    $sc.Save()
    return $lnk
}

# ---------------------------------------------------------------------------
Show-Header
$cfg = Load-Config
$tmp = $null
try {
    # 1) Where is WoW: Forever?
    $root = $null
    if ($cfg.wowRoot -and (Test-WowRoot $cfg.wowRoot)) { $root = $cfg.wowRoot }
    if (-not $root) { $root = Find-WowRoot }
    if (-not $root) { $root = Pick-WowRoot }
    if (-not $root) { throw 'WoW: Forever was not found. Run this again and pick your World of Warcraft folder.' }
    $cfg.wowRoot = $root
    Save-Config $cfg
    $addons = Join-Path $root '_forever_\Interface\AddOns'
    New-Item -ItemType Directory -Force -Path $addons | Out-Null
    $dest = Join-Path $addons $Addon
    Say ('WoW: Forever   ' + $root)

    # 2) Versions
    $localToc = Join-Path $dest ($Addon + '.toc')
    $localVer = $null
    if (Test-Path -LiteralPath $localToc) { $localVer = Get-TocVersion (Get-Content -LiteralPath $localToc -Raw) }
    $stamp = [DateTime]::UtcNow.Ticks
    $rawUrl = "https://raw.githubusercontent.com/$Repo/$Branch/$Addon.toc?nocache=$stamp"
    $remoteVer = Get-TocVersion ((Invoke-WebRequest -Uri $rawUrl -UseBasicParsing).Content)
    if (-not $remoteVer) { throw 'Could not read the latest version from GitHub.' }
    Say ('Installed      ' + $(if ($localVer) { $localVer } else { 'not installed' }))
    Say ('Latest         ' + $remoteVer)
    Say ''

    if ($localVer -and -not $Force -and (Compare-Versions $localVer $remoteVer) -ge 0) {
        Say 'You are up to date. Positions unchanged.' 'Green'
    } else {
        # 3) Download + unpack
        Say 'Downloading the latest version...' 'Cyan'
        $tmp = Join-Path $env:TEMP ('FishPartners-update-' + $stamp)
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'addon.zip'
        Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
        $unz = Join-Path $tmp 'unz'
        Expand-Archive -LiteralPath $zip -DestinationPath $unz -Force
        $tocFile = Get-ChildItem -LiteralPath $unz -Recurse -Filter ($Addon + '.toc') | Select-Object -First 1
        if (-not $tocFile) { throw 'The download did not contain the addon. Try again in a minute.' }
        $src = $tocFile.Directory.FullName
        foreach ($junk in @('.github', 'tools', '.gitignore', '.gitattributes')) {
            $j = Join-Path $src $junk
            if (Test-Path -LiteralPath $j) { Remove-Item -LiteralPath $j -Recurse -Force }
        }

        # 4) Swap folders safely (old version is restored if anything fails)
        $backup = $dest + '.fp-backup'
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if (Test-Path -LiteralPath $dest) { Move-Item -LiteralPath $dest -Destination $backup }
        try {
            Copy-Item -LiteralPath $src -Destination $dest -Recurse
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        } catch {
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $dest }
            throw
        }

        Say ('Booked: Fish & Partners ' + $remoteVer + ' installed.') 'Green'
        $notes = Get-ChangelogSection (Join-Path $dest 'CHANGELOG.md') $remoteVer
        if ($notes.Count -gt 0) {
            Say ''
            Say "What's new:" 'DarkYellow'
            foreach ($n in $notes) { Say ('  ' + $n) }
        }
        if (Get-Process | Where-Object { $_.ProcessName -match '^Wow' }) {
            Say ''
            Say 'WoW is running: type /reload in game to load the new version.' 'Yellow'
        }
    }

    # 5) Offer auto-update at Windows login (asked once)
    if (-not $Silent -and -not $cfg.autostartAsked) {
        Say ''
        $answer = Read-Host 'Check for updates automatically every time Windows starts? (y/N)'
        $cfg.autostartAsked = $true
        Save-Config $cfg
        if ($answer -match '^(y|yes|j|ja)$') {
            $lnk = Install-Autostart
            Say 'Done. Keep this file where it is; the login shortcut runs it from here.' 'Green'
            Say ('To undo, delete: ' + $lnk) 'DarkGray'
        }
    }
    $exitCode = 0
} catch {
    Say ''
    Say ('Update failed: ' + $_.Exception.Message) 'Red'
    $exitCode = 1
} finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Say ''
exit $exitCode
