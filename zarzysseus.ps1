#Requires -Version 5.1
<#
Zarzysseus: native Windows companion for the Odysseus Linux installer.
Use PowerShell 5.1+ (Windows 10/11). No WSL required for the core application.
Commands: tui, install, start, stop, restart, status, enable, disable,
repo-update, hf-token, hf-token-status, hf-token-clear, ollama-install,
ollama-start, ollama-pull, models, skills, skills-fix-all, accelerator-status,
network-mode localhost|lan|status.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Action = 'tui',
    [Parameter(Position=1)][string]$Argument = ''
)
$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/odysseus-dev/odysseus.git'
$StateDir = Join-Path $env:LOCALAPPDATA 'Zarzysseus'
$StateFile = Join-Path $StateDir 'project-path.txt'
$TokenFile = Join-Path $StateDir 'hf-token.dpapi'
$PidFile = Join-Path $StateDir 'odysseus.pid'
$LogFile = Join-Path $StateDir 'odysseus.log'
$ManagedScript = Join-Path $StateDir 'zarzysseus.ps1'
$StartupFile = Join-Path ([Environment]::GetFolderPath('Startup')) 'Zarzysseus-Odysseus.cmd'
$Port = if ($env:ODYSSEUS_PORT) { $env:ODYSSEUS_PORT } else { '7000' }
$NetworkHostFile = Join-Path $StateDir 'network-host.txt'
$ProjectDir = $null
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
# Align with the Linux default. A 0.0.0.0 listener may be reachable from LAN
# and other routed interfaces; no Windows Firewall rules are opened automatically.
$BindHost = '0.0.0.0'
if (Test-Path -LiteralPath $NetworkHostFile) {
    $savedHost = (Get-Content -LiteralPath $NetworkHostFile -Raw).Trim()
    if ($savedHost -in @('0.0.0.0','127.0.0.1')) { $BindHost = $savedHost }
}
if ($env:ZARZYSSEUS_HOST -in @('0.0.0.0','127.0.0.1')) { $BindHost = $env:ZARZYSSEUS_HOST }

function Say([string]$message) { Write-Host ('==> ' + $message) -ForegroundColor Cyan }
function Okay([string]$message) { Write-Host ('    [ready] ' + $message) -ForegroundColor Green }
function Warn([string]$message) { Write-Host ('    [warning] ' + $message) -ForegroundColor Yellow }
function Fail([string]$message) { throw $message }
function Have([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Invoke-Checked([string]$exe,[string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { Fail ("Command failed ($LASTEXITCODE): $exe " + ($arguments -join ' ')) }
}
function Is-Checkout([string]$directory) {
    if (-not $directory) { return $false }
    return ((Test-Path -LiteralPath (Join-Path $directory '.git')) -and
            ((Test-Path -LiteralPath (Join-Path $directory 'app.py')) -or
             (Test-Path -LiteralPath (Join-Path $directory 'pyproject.toml'))))
}
function Find-Project {
    if ($env:PROJECT_DIR) { return $env:PROJECT_DIR }
    $places = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $StateFile) { [void]$places.Add((Get-Content -LiteralPath $StateFile -Raw).Trim()) }
    [void]$places.Add($PSScriptRoot)
    [void]$places.Add((Split-Path -Parent $PSScriptRoot))
    foreach ($name in @('odysseus','Odysseus','Zarzysseus','Projects\odysseus','src\odysseus','Documents\odysseus','Downloads\odysseus')) {
        [void]$places.Add((Join-Path $HOME $name))
    }
    foreach ($directory in $places) {
        if (Is-Checkout $directory) { return (Resolve-Path -LiteralPath $directory).Path }
    }
    # Search only the immediate children of typical checkout parents. Avoid an unbounded HOME walk.
    foreach ($parent in @($HOME,(Join-Path $HOME 'Projects'),(Join-Path $HOME 'src'),(Join-Path $HOME 'Documents'))) {
        if (-not (Test-Path -LiteralPath $parent)) { continue }
        foreach ($child in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
            if (Is-Checkout $child.FullName) { return $child.FullName }
        }
    }
    return (Join-Path $HOME 'odysseus')
}
function Save-Project { Set-Content -LiteralPath $StateFile -Value $ProjectDir -Encoding UTF8 }
function Ensure-Winget {
    if (-not (Have 'winget')) { Fail 'WinGet is needed for automatic Windows prerequisites. Install App Installer from Microsoft or install Git/Python manually.' }
}
function Refresh-UserPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path
    foreach ($path in @('C:\Program Files\Git\cmd','C:\Program Files\Git\bin',
                        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd'),
                        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama'))) {
        if (Test-Path -LiteralPath $path) { $env:Path = $path + ';' + $env:Path }
    }
}
function Ensure-Git {
    if (Have 'git') { return }
    Ensure-Winget
    Say 'Installing Git for Windows (Git Bash is also useful to Odysseus Cookbook)'
    Invoke-Checked 'winget' @('install','--id','Git.Git','-e','--accept-package-agreements','--accept-source-agreements')
    Refresh-UserPath
    if (-not (Have 'git')) { Fail 'Git installed but is not yet on PATH. Open a new terminal, then rerun.' }
}
function Get-PythonLauncher {
    $candidates = @(
        @{ Bin='py'; Args=@('-3.12') },
        @{ Bin='py'; Args=@('-3.11') },
        @{ Bin='python'; Args=@() }
    )
    foreach ($c in $candidates) {
        if (-not (Have $c.Bin)) { continue }
        try {
            $pyArgs = @($c.Args)
            $version = & $c.Bin @pyArgs -c 'import sys;print("%s.%s" % sys.version_info[:2])' 2>$null
            if ($LASTEXITCODE -eq 0 -and [version]($version | Select-Object -Last 1) -ge [version]'3.11') { return $c }
        } catch { }
    }
    return $null
}
function Ensure-Python {
    $candidate = Get-PythonLauncher
    if ($candidate) { return $candidate }
    Ensure-Winget
    Say 'Installing Python 3.12 (native Windows)'
    Invoke-Checked 'winget' @('install','--id','Python.Python.3.12','-e','--accept-package-agreements','--accept-source-agreements')
    Refresh-UserPath
    $candidate = Get-PythonLauncher
    if (-not $candidate) { Fail 'Python was installed but is not available to this terminal yet. Open a new PowerShell window and rerun.' }
    return $candidate
}
function Update-Repo {
    if (-not (Is-Checkout $ProjectDir)) { return }
    if (-not (Have 'git')) { Warn 'Git not available; cannot update existing checkout.'; return }
    Say "Checking upstream Odysseus: $ProjectDir"
    $remote = (& git -C $ProjectDir remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or $remote -notmatch '(^|[/:])odysseus-dev/odysseus(\.git)?$') {
        Warn 'Checkout is not using the official upstream origin; leaving it unchanged.'; return
    }
    & git -C $ProjectDir diff --quiet --exit-code -- 2>$null
    $dirty = ($LASTEXITCODE -ne 0)
    & git -C $ProjectDir diff --cached --quiet --exit-code -- 2>$null
    $dirty = $dirty -or ($LASTEXITCODE -ne 0)
    if ($dirty) { Warn 'Tracked local edits present; preserving checkout (no automatic merge).'; return }
    $branch = (& git -C $ProjectDir symbolic-ref --quiet --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $branch) { Warn 'Detached HEAD; skipping automatic merge.'; return }
    & git -C $ProjectDir fetch --prune origin
    if ($LASTEXITCODE -ne 0) { Warn 'Network fetch failed; continuing with installed checkout.'; return }
    & git -C $ProjectDir show-ref --verify --quiet "refs/remotes/origin/$branch"
    if ($LASTEXITCODE -ne 0) { Warn "No matching origin/$branch branch; skipping merge."; return }
    & git -C $ProjectDir merge-base --is-ancestor HEAD "origin/$branch"
    if ($LASTEXITCODE -ne 0) { Warn 'Local branch diverges; no reset or force-pull attempted.'; return }
    & git -C $ProjectDir merge --ff-only "origin/$branch"
    if ($LASTEXITCODE -ne 0) { Warn 'Fast-forward blocked; local files left unchanged.'; return }
    Okay 'Upstream checkout is current.'
}
function Ensure-Project {
    Ensure-Git
    if (-not (Is-Checkout $ProjectDir)) {
        if (Test-Path -LiteralPath $ProjectDir) { Fail "Non-Odysseus directory already exists: $ProjectDir. Set PROJECT_DIR to another path." }
        Say "Cloning Odysseus to $ProjectDir"
        Invoke-Checked 'git' @('clone',$RepoUrl,$ProjectDir)
    } else { Update-Repo }
    Save-Project
    Copy-Item -LiteralPath $PSCommandPath -Destination $ManagedScript -Force
}
function Get-VenvPython { return (Join-Path $ProjectDir 'venv\Scripts\python.exe') }
function Ensure-Venv {
    $venvPy = Get-VenvPython
    if (-not (Test-Path -LiteralPath $venvPy)) {
        $python = Ensure-Python
        Say 'Creating isolated native Windows Python environment'
        $pyArgs = @($python.Args)
        & $python.Bin @pyArgs -m venv (Join-Path $ProjectDir 'venv')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $venvPy)) { Fail 'venv creation failed; check Windows Python launcher.' }
    }
    return $venvPy
}
function Load-HFToken {
    if (-not (Test-Path -LiteralPath $TokenFile)) { return }
    try {
        $secure = (Get-Content -LiteralPath $TokenFile -Raw).Trim() | ConvertTo-SecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $env:HF_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch { Warn 'Unable to decrypt stored Hugging Face token for this Windows user.' }
}
function HF-Token {
    Write-Host 'Create a read/fine-grained token at: https://huggingface.co/settings/tokens' -ForegroundColor Cyan
    Write-Host 'Public models work without a token. Gated models may also require accepting the model license.'
    $secure = Read-Host 'Paste your token (hidden)' -AsSecureString
    if ($secure.Length -eq 0) { Warn 'No token entered.'; return }
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $TokenFile -Encoding UTF8
    Load-HFToken
    if ($env:HF_TOKEN -notmatch '^hf_') { Warn 'Stored token does not start with hf_; verify it in Hugging Face settings.' }
    Okay 'Token encrypted for this Windows user. It will not appear in the repair log.'
    if (Test-Path -LiteralPath (Get-VenvPython)) {
        $python = Get-VenvPython
        & $python -m pip show huggingface_hub *> $null
        if ($LASTEXITCODE -eq 0) {
            & $python -c 'import os;from huggingface_hub import login;login(token=os.environ["HF_TOKEN"],add_to_git_credential=False)'
            if ($LASTEXITCODE -ne 0) { Warn 'Hub login check failed; token is still encrypted locally.' }
        }
    }
}
function HF-Status {
    Load-HFToken
    if ($env:HF_TOKEN) { Okay 'Hugging Face token configured (value hidden).' }
    else { Warn 'Hugging Face token not set. Recommended: choose Hugging Face Setup.' }
}
function HF-Clear {
    Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
    Remove-Item Env:HF_TOKEN -ErrorAction SilentlyContinue
    Okay 'Zarzysseus encrypted token cleared. Other Hugging Face clients may retain separate credentials.'
}
function Install-Stack {
    Ensure-Project
    $python = Ensure-Venv
    Say 'Installing native Odysseus requirements (no full Windows OS upgrade)'
    Invoke-Checked $python @('-m','pip','install','--upgrade','pip')
    Invoke-Checked $python @('-m','pip','install','-r',(Join-Path $ProjectDir 'requirements.txt'))
    Say 'Running upstream Odysseus setup'
    Push-Location $ProjectDir
    try { Invoke-Checked $python @('setup.py') }
    finally { Pop-Location }
    Okay 'Odysseus environment created; start it from the menu or with start.'
}
function Current-Process {
    if (-not (Test-Path -LiteralPath $PidFile)) { return $null }
    $idValue = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if ($idValue -notmatch '^\d+$') { return $null }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $idValue" -ErrorAction SilentlyContinue
    if ($proc -and $proc.CommandLine -match 'uvicorn' -and $proc.CommandLine -match 'app:app') { return $proc }
    return $null
}
function Get-LanIPv4 {
    try {
        @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                           $_.AddressState -eq 'Preferred' } |
            Select-Object -ExpandProperty IPAddress -Unique)
    } catch {
        Warn 'Could not list LAN addresses automatically. Run ipconfig for IPv4 Address.'
        @()
    }
}
function Show-Network {
    Write-Host "Listener: $BindHost`:$Port"
    Write-Host "On this computer: http://127.0.0.1:$Port"
    if ($BindHost -eq '0.0.0.0') {
        Write-Host 'Mode: Local network / all interfaces (not just the LAN)' -ForegroundColor Yellow
        foreach ($ip in @(Get-LanIPv4)) { Write-Host "Other-device URL: http://${ip}:$Port" -ForegroundColor Cyan }
        Write-Host 'Use a trusted network. Firewall/access-control settings may block remote connections.'
        Write-Host 'Do not expose this service by port forwarding or public firewall rules.'
    } else {
        Write-Host 'Mode: Localhost only; other devices cannot connect to this listener.' -ForegroundColor Green
    }
    if ($env:ZARZYSSEUS_HOST) { Warn 'ZARZYSSEUS_HOST can override the stored selection on the next launch.' }
}
function Set-Network([string]$Mode) {
    switch ($Mode.ToLowerInvariant()) {
        {$_ -in @('localhost','local','127.0.0.1')} { $newHost='127.0.0.1'; break }
        {$_ -in @('lan','network','0.0.0.0')} { $newHost='0.0.0.0'; break }
        default { Fail 'Usage: zarzysseus.ps1 network-mode localhost|lan|status' }
    }
    Set-Content -LiteralPath $NetworkHostFile -Value $newHost -Encoding ASCII
    $script:BindHost = $newHost
    # Keep the auto-start copy aligned with the script that just saved the setting.
    if ($PSCommandPath -and ($PSCommandPath -ne $ManagedScript)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $ManagedScript -Force
    }
    $wasRunning = [bool](Current-Process)
    if ($wasRunning) {
        Say 'Restarting managed Odysseus so its listener actually changes...'
        Stop-App
        Start-App
        if (-not (Current-Process)) { Fail 'Listener saved, but the managed server did not restart. Check logs.' }
    } else { Say 'Mode saved; it takes effect the next time you start Odysseus.' }
    Show-Network
}
function Network-Menu {
    while ($true) {
        Write-Host "`nNETWORK DISCOVERABILITY" -ForegroundColor Cyan
        Show-Network
        Write-Host '1  Localhost only (127.0.0.1)'
        Write-Host '2  Local network / all interfaces (0.0.0.0)'
        Write-Host '3  Refresh connection addresses'
        Write-Host '0  Back'
        switch (Read-Host 'Choose') {
            '1' { Set-Network 'localhost' }
            '2' { Set-Network 'lan' }
            '3' { Show-Network }
            '0' { return }
            default { Warn 'Unknown choice.' }
        }
    }
}
function Start-App {
    $existing = Current-Process
    if ($existing) { Okay "Odysseus already running (PID $($existing.ProcessId))."; return }
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { Fail 'Install the Odysseus stack first.' }
    Load-HFToken
    Say "Starting native Odysseus (listening on ${BindHost}:$Port)"
    $args = @('-m','uvicorn','app:app','--host',$BindHost,'--port',$Port)
    $proc = Start-Process -FilePath $python -ArgumentList $args -WorkingDirectory $ProjectDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError (Join-Path $StateDir 'odysseus.err.log')
    Set-Content -LiteralPath $PidFile -Value $proc.Id
    Start-Sleep -Seconds 2
    if (Current-Process) { Okay "Server started (PID $($proc.Id))."; Show-Network }
    else { Warn 'Server exited during startup. Check logs in the Zarzysseus state directory.' }
}
function Stop-App {
    $proc = Current-Process
    if (-not $proc) { Warn 'No managed running server.'; return }
    Stop-Process -Id $proc.ProcessId -Force
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Okay 'Managed Odysseus server stopped.'
}
function Show-Status {
    Write-Host "Project: $ProjectDir"
    Show-Network
    Write-Host "Python environment: $(Test-Path -LiteralPath (Get-VenvPython))"
    $proc = Current-Process
    if ($proc) { Okay "Server running, PID $($proc.ProcessId)" }
    else { Warn 'Managed server not running.' }
    HF-Status
}
function Enable-Startup {
    if ($PSCommandPath -and ($PSCommandPath -ne $ManagedScript)) { Copy-Item -LiteralPath $PSCommandPath -Destination $ManagedScript -Force }
    $line = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ManagedScript + '" start' + "`r`n"
    Set-Content -LiteralPath $StartupFile -Value $line -Encoding ASCII
    Okay 'Current-user startup enabled (Startup folder, no administrator required).'
}
function Disable-Startup {
    Remove-Item -LiteralPath $StartupFile -Force -ErrorAction SilentlyContinue
    Okay 'Current-user startup disabled.'
}
function Ensure-Ollama {
    if (Have 'ollama') { return }
    Ensure-Winget
    Say 'Installing Ollama for native Windows local inference'
    Invoke-Checked 'winget' @('install','--id','Ollama.Ollama','-e','--accept-package-agreements','--accept-source-agreements')
    Refresh-UserPath
    if (-not (Have 'ollama')) { Fail 'Ollama installed, but cannot be found. Reopen PowerShell and rerun.' }
}
function Start-Ollama {
    Ensure-Ollama
    try {
        $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
        Okay 'Ollama already serving on localhost:11434'; return
    } catch { }
    $app = (Get-Command ollama).Source
    Start-Process -FilePath $app -ArgumentList @('serve') -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
    Okay 'Ollama launch requested; check http://localhost:11434/api/tags.'
}
function Pull-Ollama([string]$model) {
    if (-not $model -or $model -notmatch '^[\w./:-]+$') { Fail 'Supply a valid Ollama model tag.' }
    Start-Ollama
    Invoke-Checked 'ollama' @('pull',$model)
}
function Show-Accelerator {
    Say 'Windows graphics adapters (informational; driver installation is not automated)'
    Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,@{Name='VRAM_GB_est';Expression={if ($_.AdapterRAM) {[math]::Round($_.AdapterRAM / 1GB,1)} else {'unknown'}}} | Format-Table -AutoSize
    Write-Host 'Use Ollama for native Windows local models. vLLM/SGLang and ROCm are Linux/WSL2 paths.'
    Write-Host 'Windows WMI VRAM is frequently truncated for large GPUs; do not treat it as an exact fit test.'
}
function Ensure-Hub {
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { Fail 'Install the Odysseus stack before downloading Hub media models.' }
    & $python -c 'import huggingface_hub' *> $null
    if ($LASTEXITCODE -ne 0) { Invoke-Checked $python @('-m','pip','install','huggingface_hub') }
    return $python
}
function Download-Hub([string]$repo) {
    if ($repo -notmatch '^[\w.-]+/[\w.-]+$') { Fail 'Expected a Hugging Face org/model repository ID.' }
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) {
        Say 'First confirmed Hub download: preparing native Odysseus stack once'
        Install-Stack
    }
    $python = Ensure-Hub
    Load-HFToken
    Say "Downloading Hub snapshot: $repo (availability and model terms may vary)"
    $env:ZARZYSSEUS_DOWNLOAD_REPO = $repo
    $env:ZARZYSSEUS_MODEL_DIR = Join-Path $StateDir 'models'
    $code = 'import os;from pathlib import Path;from huggingface_hub import snapshot_download;r=os.environ["ZARZYSSEUS_DOWNLOAD_REPO"];dest=Path(os.environ["ZARZYSSEUS_MODEL_DIR"])/r;dest.mkdir(parents=True,exist_ok=True);print(snapshot_download(repo_id=r,local_dir=str(dest)))'
    & $python -c $code
    if ($LASTEXITCODE -ne 0) { Fail "Download failed for $repo. Check access, disk space, and Hugging Face token." }
    Okay "Downloaded $repo. Media models require a compatible runtime for inference; snapshot alone is not a working generator."
}
function Catalog {
    return @(
      [pscustomobject]@{Family='Normal';Type='Text';Name='Llama 3.1 8B';Id='llama3.1:8b';Source='Ollama';Params='8B';Size='~4.9 GB'},
      [pscustomobject]@{Family='Normal';Type='Text';Name='Qwen3 8B';Id='qwen3:8b';Source='Ollama';Params='8B';Size='~5 GB'},
      [pscustomobject]@{Family='L.P.S.';Type='Text';Name='Qwen3 0.6B';Id='qwen3:0.6b';Source='Ollama';Params='0.6B';Size='~0.5 GB'},
      [pscustomobject]@{Family='L.P.S.';Type='Text';Name='SmolLM2 360M';Id='smollm2:360m';Source='Ollama';Params='360M';Size='~0.3 GB'},
      [pscustomobject]@{Family='Normal';Type='Photo';Name='Stable Diffusion Turbo';Id='stabilityai/sd-turbo';Source='Hub';Params='~0.86B*';Size='model repo varies'},
      [pscustomobject]@{Family='L.P.S.';Type='Photo';Name='Tiny SD';Id='segmind/tiny-sd';Source='Hub';Params='~0.33B*';Size='model repo varies'},
      [pscustomobject]@{Family='Normal';Type='Video';Name='ZeroScope V2';Id='cerspense/zeroscope_v2_576w';Source='Hub';Params='N/P';Size='large; check repo'},
      [pscustomobject]@{Family='Normal';Type='Audio';Name='Whisper Base';Id='openai/whisper-base';Source='Hub';Params='74M';Size='~0.3 GB'},
      [pscustomobject]@{Family='L.P.S.';Type='Audio';Name='Whisper Tiny';Id='openai/whisper-tiny';Source='Hub';Params='39M';Size='~0.15 GB'}
    )
}
function Model-Browser {
    $items = @(Catalog)
    $families = @('Normal','L.P.S.','Desert Ant')
    $types = @('All','Text','Photo','Video','Audio')
    $family = 0; $type = 0; $cursor = 0
    $selected = New-Object 'System.Collections.Generic.HashSet[string]'
    while ($true) {
        $visible = @($items | Where-Object { $_.Family -eq $families[$family] -and ($types[$type] -eq 'All' -or $_.Type -eq $types[$type]) })
        if ($cursor -ge $visible.Count) { $cursor = [math]::Max(0,$visible.Count-1) }
        Clear-Host
        Write-Host 'ZARZYSSEUS  /  MANUAL MODEL SELECTION' -ForegroundColor Cyan
        Write-Host "Family [Tab]: $($families[$family])    Type [1-5]: $($types[$type])"
        Write-Host 'Up/Down browse | Space mark | D details | I install marked | Esc cancel' -ForegroundColor DarkGray
        Write-Host "Marked: $($selected.Count). No updates or installs happen until I and confirmation." -ForegroundColor Yellow
        Write-Host ''
        if ($families[$family] -eq 'Desert Ant') {
            Write-Host 'Desert Ant SDK supports Windows x64 (Swift/LiteRT), but has no native Windows model CLI managed by this script.'
            Write-Host 'It is a specialist SDK, not a text/photo/video generator.'
        } elseif ($visible.Count -eq 0) { Write-Host 'No models in this category.' }
        for ($i=0; $i -lt $visible.Count; $i++) {
            $m=$visible[$i]; $mark=if($selected.Contains($m.Id)){'[x]'}else{'[ ]'}
            $arrow=if($i -eq $cursor){'>'}else{' '}
            $line=" $arrow $mark $($m.Type.PadRight(5)) $($m.Name.PadRight(24)) $($m.Params.PadRight(8)) $($m.Size)"
            if ($i -eq $cursor) { Write-Host $line -ForegroundColor Cyan } else { Write-Host $line }
        }
        Write-Host "`n* parameter estimates; N/P = not published; sizes vary with files/quantization." -ForegroundColor DarkGray
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Escape' { return }
            'Tab' { if (($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0) {$type=($type+1)%5} else {$family=($family+1)%3};$cursor=0 }
            'D1' {$type=0;$cursor=0};'D2' {$type=1;$cursor=0};'D3' {$type=2;$cursor=0};'D4' {$type=3;$cursor=0};'D5' {$type=4;$cursor=0}
            'UpArrow' { $cursor=[math]::Max(0,$cursor-1) }
            'DownArrow' { $cursor=[math]::Min([math]::Max(0,$visible.Count-1),$cursor+1) }
            'Spacebar' { if($visible.Count) { $id=$visible[$cursor].Id; if(-not $selected.Add($id)) {[void]$selected.Remove($id)} } }
            'D' {if($visible.Count){ $m=$visible[$cursor];Write-Host "`n$($m.Name): $($m.Type) / $($m.Family) / $($m.Params) parameters / $($m.Size)";Write-Host "Source: $($m.Source)  ID: $($m.Id)";[void](Read-Host 'Enter to return') }}
            'I' {
                if($selected.Count -eq 0) {continue}
                Write-Host "`nWill install $($selected.Count) selected model(s); prerequisites may be installed."
                if((Read-Host 'Type YES to confirm').Trim() -cne 'YES'){continue}
                # Important: no repo/OS/model installation before this confirmation.
                foreach($model in $items | Where-Object {$selected.Contains($_.Id)}) {
                    try { if($model.Source -eq 'Ollama'){Pull-Ollama $model.Id}else{Download-Hub $model.Id} }
                    catch { Warn "$($model.Name): $($_.Exception.Message)" }
                }
                [void](Read-Host 'Enter to return to menu');return
            }
        }
    }
}
function Skill-Roots {
    $roots = @((Join-Path $ProjectDir 'data\skills\imported'),(Join-Path $HOME '.agents\skills'),(Join-Path $StateDir 'skills'))
    foreach($root in $roots){if(Test-Path -LiteralPath $root){Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')}}}
}
function Fix-Skill([string]$folder) {
    Say "Checking skill: $(Split-Path $folder -Leaf)"
    $problems=0
    $requirements=Join-Path $folder 'requirements.txt'
    $package=Join-Path $folder 'package.json'
    if(Test-Path -LiteralPath $requirements){
        $python=Get-VenvPython
        if (-not (Test-Path $python)){Warn 'Python env missing; install stack first.';$problems++}
        else{ & $python -m pip install -r $requirements; if($LASTEXITCODE -ne 0){$problems++} }
    }
    if(Test-Path -LiteralPath $package){
        if (-not (Have 'npm')){
            if(Have 'winget'){Say 'Installing Node.js LTS for declared npm skill dependencies'; & winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements;Refresh-UserPath}
            if (-not (Have 'npm')){Warn 'npm absent. Install Node.js LTS to repair this skill.';$problems++}
        }
        if(Have 'npm'){ Push-Location $folder;try{& npm install --ignore-scripts; if($LASTEXITCODE -ne 0){$problems++}}finally{Pop-Location} }
    }
    if (-not (Test-Path $requirements) -and -not (Test-Path $package)){Warn 'No machine-readable requirements manifest; not claiming end-to-end verification.'}
    if($problems -eq 0){Okay 'Declared prerequisites checked.'}else{Warn "$problems unresolved prerequisite(s)."}
    return $problems
}
function Fix-All-Skills {
    $roots=@(Skill-Roots | Sort-Object Name -Unique)
    if($roots.Count -eq 0){Warn 'No installed SKILL.md folders found.';return}
    $failed=0
    for($i=0;$i -lt $roots.Count;$i++){
        Write-Host "`n[$($i+1)/$($roots.Count)] $($roots[$i].Name)" -ForegroundColor Cyan
        $failed += Fix-Skill $roots[$i].FullName
    }
    if($failed){Warn "$failed unresolved prerequisites across checked skills."}else{Okay 'All declared requirements processed. Undeclared runtime behavior is not inferred.'}
}
function Fave-Skills {
    $base=Join-Path $StateDir 'skills'
    $descriptions=@{
       'fave-office'='Use python-docx, openpyxl, python-pptx and pypdf for local Office files; request confirmation before overwriting originals.';
       'fave-photo-edit'='Use Pillow for local image crop/resize/color operations; do not claim generative editing unless a model is configured.';
       'fave-video-edit'='Use FFmpeg for local trim, transcode, subtitles and audio extraction; check ffmpeg availability first.';
       'fave-scripting'='Use Python and PowerShell for scripting; use ruff for Python linting.';
       'fave-transcription'='Use faster-whisper for speech-to-text; model weights download separately on first use.'
    }
    $python=Get-VenvPython
    if (-not (Test-Path $python)){Fail 'Install the Odysseus stack first to install Python skill dependencies.'}
    Invoke-Checked $python @('-m','pip','install','python-docx','openpyxl','python-pptx','pypdf','Pillow','ruff','faster-whisper')
    foreach($name in $descriptions.Keys){
        $dir=Join-Path $base $name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $md='---'+"`n"+'name: '+$name+"`n"+'description: '+$descriptions[$name]+"`n"+'---'+"`n`n"+'# '+$name+"`n`n"+$descriptions[$name]+"`n"
        Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $md -Encoding UTF8
        Okay "Local skill template installed: $name"
    }
    Warn 'Templates are stored in the Zarzysseus state directory. Upstream UI import/registration is not guaranteed by this companion.'
}
function Skills-Menu {
    while($true){
        Write-Host "`nSKILLS  [1] Install Fave templates  [2] Fix All declared dependencies  [3] List installed  [0] Back"
        switch(Read-Host 'Choose'){
            '1'{Fave-Skills};'2'{Fix-All-Skills};'3'{Skill-Roots | Select-Object -ExpandProperty FullName | Sort-Object -Unique};'0'{return}
        }
    }
}
function Main-Menu {
    while($true){
        Write-Host ''
        Write-Host '================== ZARZYSSEUS / WINDOWS ==================' -ForegroundColor Cyan
        Write-Host "Odysseus: $ProjectDir"
        Write-Host '1  Install / Update native Windows Odysseus'
        Write-Host '2  Start server       3  Stop server       4  Status'
        Write-Host '5  Manual model browser (choose BEFORE downloading)'
        Write-Host '6  Ollama setup       7  Skills / Fix All'
        Write-Host '8  Hugging Face setup (recommended)'
        Write-Host '9  Accelerator status / Windows limitations'
        Write-Host '10 Enable startup    11 Disable startup'
        Write-Host '12 Update upstream Git checkout'
        Write-Host '13 Network Discoverability (localhost / LAN)'
        Write-Host '0  Exit'
        Write-Host 'Tip: star https://github.com/zarzorr69/zarzyssues if it helps you!' -ForegroundColor DarkCyan
        $choice=Read-Host 'Choose'
        try{
            switch($choice){
                '1'{Install-Stack};'2'{Start-App};'3'{Stop-App};'4'{Show-Status};
                '5'{Model-Browser};'6'{Start-Ollama};'7'{Skills-Menu};'8'{HF-Token};
                '9'{Show-Accelerator};'10'{Enable-Startup};'11'{Disable-Startup};
                '12'{Update-Repo};'13'{Network-Menu};'0'{return};default{Warn 'Unknown choice.'}
            }
        }catch{Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red}
    }
}

try {
    $ProjectDir = Find-Project
    Load-HFToken
    # Fresh fetch on launch only for an existing checkout. No OS update and no cloning just to view TUI.
    if($Action -eq 'tui' -and (Is-Checkout $ProjectDir)){Update-Repo}
    switch($Action.ToLowerInvariant()){
        'tui'{Main-Menu};'install'{Install-Stack};'start'{Start-App};'stop'{Stop-App};
        'restart'{Stop-App;Start-App};'status'{Show-Status};'enable'{Enable-Startup};
        'disable'{Disable-Startup};'repo-update'{Update-Repo};'hf-token'{HF-Token};
        'hf-token-status'{HF-Status};'hf-token-clear'{HF-Clear};
        'ollama-install'{Ensure-Ollama};'ollama-start'{Start-Ollama};
        'ollama-pull'{Pull-Ollama $Argument};'models'{Model-Browser};'skills'{Skills-Menu};
        'skills-fix-all'{Fix-All-Skills};'accelerator-status'{Show-Accelerator};
        'network-mode'{if ($Argument -eq 'status' -or -not $Argument) { Show-Network } else { Set-Network $Argument }};
        default{Fail "Unknown command: $Action"}
    }
}catch{Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
