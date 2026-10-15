#Requires -Version 5.1
<#
Zarzysseus Docker Desktop controller (Windows, Linux containers only).
Uses the same Compose CPU kit and in-container agent/skills/MCP bridge as Linux.
Host-only features are not silently emulated in containers.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Action='tui',
    [Parameter(Position=1)][string]$Argument='',
    [Parameter(Position=2)][string]$Extra=''
)
$ErrorActionPreference='Stop'
$KitDir=$PSScriptRoot
$ModeDir=Join-Path $env:LOCALAPPDATA 'Zarzysseus'
$HardwareFile=Join-Path $ModeDir 'hardware-docker.txt'
$MainScript=Join-Path (Split-Path -Parent $KitDir) 'zarzysseus.ps1'
function Explain([string]$msg) { Write-Host $msg -ForegroundColor Cyan }
function Warn([string]$msg) { Write-Host $msg -ForegroundColor Yellow }
function Require([bool]$condition,[string]$message) { if(-not $condition) { throw $message } }
function Get-Profile {
    if(Test-Path -LiteralPath $HardwareFile) {
        $p=(Get-Content -LiteralPath $HardwareFile -Raw).Trim().ToLowerInvariant()
        if($p -in @('cpu','full')) { return $p }
    }
    return 'cpu'
}
function Confirm([string]$token,[string]$message) {
    if(-not [Environment]::UserInteractive) { throw 'Interactive confirmation is required.' }
    Write-Host $message -ForegroundColor Yellow
    $answer=Read-Host "Type $token to continue"
    return ($answer -ceq $token)
}
function Check-Docker {
    Require ([bool](Get-Command docker -ErrorAction SilentlyContinue)) 'Docker CLI missing. Install and start Docker Desktop with Linux containers first.'
    & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    Require ($LASTEXITCODE -eq 0) 'Docker Desktop daemon is unavailable. Start Docker Desktop and enable Linux containers.'
    & docker compose version 2>$null | Out-Null
    Require ($LASTEXITCODE -eq 0) 'Docker Compose v2 is unavailable. Install/update Docker Desktop.'
}
function Invoke-Docker([string[]]$Arguments) {
    Check-Docker
    & docker @Arguments
    if($LASTEXITCODE -ne 0) { throw "Docker exited $LASTEXITCODE while running: $($Arguments -join ' ')" }
}
function Invoke-Compose([string[]]$Arguments,[switch]$GPU) {
    $argv=@('compose','--env-file','.env','-f','compose.yaml')
    if($GPU) { $argv+=@('-f','compose.gpu.yaml') }
    Invoke-Docker ($argv + $Arguments)
}
function Confirm-Kit {
    Require (Test-Path -LiteralPath (Join-Path $KitDir 'compose.yaml')) 'Docker Compose kit not found. Download the complete Zarzysseus release ZIP, not only zarzysseus.ps1.'
    Require (Test-Path -LiteralPath (Join-Path $KitDir 'zarzysseus_bridge.py')) 'The container tool bridge is missing from the release.'
    Require (Test-Path -LiteralPath (Join-Path $KitDir 'toolkit/zarzysseus.sh')) 'The bundled agent repair toolkit is missing.'
    $envFile=Join-Path $KitDir '.env'
    if(-not (Test-Path -LiteralPath $envFile)) {
        $example=Join-Path $KitDir '.env.example'
        Require (Test-Path -LiteralPath $example) '.env.example is missing.'
        Copy-Item -LiteralPath $example -Destination $envFile
        Explain 'Created .env for this installation; existing .env files are never overwritten.'
    }
}
function Get-AppIdentity {
    $uid='999'; $gid='1000'
    foreach($line in (Get-Content -LiteralPath (Join-Path $KitDir '.env'))) {
        if($line -match '^APP_UID=(\d+)$') {$uid=$Matches[1]}
        if($line -match '^APP_GID=(\d+)$') {$gid=$Matches[1]}
    }
    return "$uid`:$gid"
}
function Invoke-Bridge([string]$Operation,[string[]]$Parameters=@()) {
    $user=Get-AppIdentity
    Invoke-Compose (@('exec','-T','--user',$user,'odysseus','python','/cpu-kit/zarzysseus_bridge.py',$Operation) + $Parameters)
}
function Invoke-Agent([string]$Name,[string[]]$Parameters=@()) {
    Invoke-Bridge 'run' (@($Name)+$Parameters)
}
function Start-Ollama {
    Invoke-Compose @('up','-d','cpu-ollama')
    for($i=0;$i -lt 60;$i++) {
        & docker compose --env-file .env -f compose.yaml exec -T cpu-ollama ollama list 2>$null | Out-Null
        if($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw 'Ollama did not become ready in 60 seconds. Inspect Docker logs.'
}
function Setup-Model([string]$Profile) {
    $profiles=@{
        quality=@('qwen3.5:4b-q4_K_M','qwen3.5-zarzysseus-cpu:4b')
        agent=@('LiquidAI/lfm2.5-2.6b:q4_k_m','lfm2.5-zarzysseus-cpu:2.6b')
        moe=@('lfm2.5:8b-a1b-q4_K_M','lfm2.5-zarzysseus-cpu:8b-a1b')
    }
    Require ($profiles.ContainsKey($Profile)) 'Choose model profile quality, agent, or moe.'
    $details=$profiles[$Profile]
    Require (Confirm 'PULL' "Download Ollama model $($details[0]) and create its CPU profile? This may download several GB.") 'Model setup cancelled.'
    Start-Ollama
    Invoke-Compose @('exec','-T','cpu-ollama','ollama','pull',$details[0])
    Invoke-Compose @('exec','-T','cpu-ollama','ollama','create',$details[1],'-f',"/profiles/Modelfile.$Profile")
    Explain "Installed $($details[1]). This does not switch your active chat model."
}
function Start-App {
    $cfg=Join-Path $KitDir 'config/searxng/settings.yml'
    if(-not (Test-Path -LiteralPath $cfg)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        $bytes=New-Object byte[] 32
        $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $secret=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
        $settings="use_default_settings: true`nserver:`n  secret_key: `"$secret`"`n  bind_address: `"0.0.0.0`"`n  port: 8080`nsearch:`n  formats:`n    - html`n    - json`n"
        [IO.File]::WriteAllText($cfg,$settings,([Text.UTF8Encoding]::new($false)))
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $KitDir 'workspace') | Out-Null
    Start-Ollama
    Invoke-Compose @('--profile','app','up','-d','odysseus')
    Explain 'Odysseus containers requested. Check status and logs; startup is not proof of health.'
}
function Get-Setting([string]$Key,[string]$Default='') {
    $envFile=Join-Path $KitDir '.env'
    $found=$Default
    foreach($line in (Get-Content -LiteralPath $envFile -ErrorAction Stop)) {
        if($line.StartsWith("$Key=")) { $found=$line.Substring($Key.Length+1) }
    }
    return $found
}
function Show-Network {
    Explain 'Current Docker web address (read only):'
    Write-Host "  Host binding: $(Get-Setting 'APP_BIND' '127.0.0.1')"
    Write-Host "  Host port:    $(Get-Setting 'APP_PORT' '7012')"
    Write-Host "  Web origins:  $(Get-Setting 'APP_ORIGIN' 'http://localhost:7012')"
    Write-Host 'Authentication remains enabled; internal container port is 7000.'
}
function Update-NetworkSettings([string]$Bind,[string]$Port,[string]$Origins) {
    # Do not interpret .env as PowerShell. Preserve all non-network entries.
    $envFile=Join-Path $KitDir '.env'
    $info=Get-Item -LiteralPath $envFile -Force
    Require (-not [bool]($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Refusing symlinked .env.'
    Require ($Origins -notmatch '[\r\n\s]') 'Invalid origins.'
    $newValues=@{APP_BIND=$Bind;APP_PORT=$Port;APP_ORIGIN=$Origins}
    $existing=@(Get-Content -LiteralPath $envFile -ErrorAction Stop)
    $seen=@{}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($line in $existing) {
        if($line -match '^(APP_BIND|APP_PORT|APP_ORIGIN)=') {
            $key=$Matches[1]
            if(-not $seen.ContainsKey($key)) { $lines.Add("$key=$($newValues[$key])");$seen[$key]=$true }
        } else { $lines.Add($line) }
    }
    foreach($key in @('APP_BIND','APP_PORT','APP_ORIGIN')) { if(-not $seen.ContainsKey($key)) { $lines.Add("$key=$($newValues[$key])") } }
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup="$envFile.zarzysseus-backup.$stamp.$PID"
    Copy-Item -LiteralPath $envFile -Destination $backup -ErrorAction Stop
    $temp=Join-Path $KitDir ('.env.zarzysseus.'+[guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllLines($temp,$lines.ToArray(),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $envFile -Force -ErrorAction Stop
    } finally { if(Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    Explain "Updated network settings. Backup: $backup"
}
function Set-Network {
    Show-Network
    Write-Host "`n1. Only this PC (127.0.0.1)"
    Write-Host '2. LAN / Tailscale IPv4 address'
    Write-Host '3. All interfaces (0.0.0.0) — requires a private network or proxy'
    Write-Host '0. Cancel'
    $choice=Read-Host 'Choose a binding'
    switch($choice) {
        '0' { return }
        '1' {$bind='127.0.0.1'}
        '2' {
            $bind=Read-Host 'Local interface IPv4 address'
            $parsed=$null
            Require ([Net.IPAddress]::TryParse($bind,[ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) 'Enter a valid IPv4 address.'
            Require ($bind -notin @('0.0.0.0','127.0.0.1')) 'Choose a non-loopback address.'
        }
        '3' { $bind='0.0.0.0' }
        default { throw 'Invalid selection.' }
    }
    $defaultPort=Get-Setting 'APP_PORT' '7012'
    $port=Read-Host "Host port [$defaultPort]"
    if(-not $port) {$port=$defaultPort}
    $num=0
    Require ([int]::TryParse($port,[ref]$num) -and $num -ge 1024 -and $num -le 65535) 'Port must be between 1024 and 65535.'
    if($bind -eq '127.0.0.1') { $origins="http://localhost:$port,http://127.0.0.1:$port" }
    else {
        $defaultOrigin=if($bind -eq '0.0.0.0'){''}else{"http://$bind`:$port"}
        $origins=Read-Host "Browser URL origin (no path) [$defaultOrigin]"
        if(-not $origins){$origins=$defaultOrigin}
        Require ($origins -match '^https?://[A-Za-z0-9._:-]+(,https?://[A-Za-z0-9._:-]+)*$' -and $origins -notmatch '://0\.0\.0\.0:') 'Enter a browser-reachable http(s)://host:port origin (not 0.0.0.0).'
        Warn 'LAN/all-interface exposure can make Odysseus accessible to other devices. Prefer VPN, HTTPS and a trusted proxy.'
    }
    Explain "New listener: $bind`:$port; allowed origins: $origins"
    Require (Confirm 'NETWORK' 'Save this binding? Existing users and data will not be changed.') 'Cancelled.'
    Update-NetworkSettings $bind $port $origins
    if(Confirm 'RECREATE' 'Recreate only Odysseus now to apply the new network binding? It will briefly disconnect.') {
        Invoke-Compose @('--profile','app','up','-d','--no-deps','--force-recreate','odysseus')
    } else { Explain 'Saved. Apply it later from Network → Apply saved binding.' }
}
function Apply-Network {
    Require (Confirm 'RECREATE' 'Recreate only Odysseus with the saved network settings?') 'Cancelled.'
    Invoke-Compose @('--profile','app','up','-d','--no-deps','--force-recreate','odysseus')
}
function Get-AdminProvisionStatus {
    $response=@(& docker compose --env-file .env -f compose.yaml run --rm --no-deps -T --entrypoint python odysseus /cpu-kit/admin_preseed.py status)
    Require ($LASTEXITCODE -eq 0) 'Unable to inspect first-run account; please check Docker logs.'
    if($response -match 'EXISTING_AUTH_PRESERVED') { return 'exists' }
    if($response -match 'FIRST_RUN_AVAILABLE') { return 'available' }
    throw 'Unexpected account status; refusing changes.'
}
function Setup-Admin {
    $state=Get-AdminProvisionStatus
    if($state -eq 'exists') {
        Explain 'An admin account already exists. Its credentials will not be replaced. Log in and use Account Settings for a password change.'
        return
    }
    Explain 'Create the FIRST admin account before Odysseus starts; password input is hidden.'
    $name=Read-Host 'Admin username [admin]'
    if(-not $name){$name='admin'}
    Require ($name -cmatch '^[A-Za-z0-9._-]{1,32}$') 'Username must contain letters/digits/._- (maximum 32).'
    $secret=Read-Host -AsSecureString 'Password (12 or more characters)'
    $second=Read-Host -AsSecureString 'Confirm password'
    $ptr=[IntPtr]::Zero; $ptr2=[IntPtr]::Zero; $plain=$null; $repeat=$null
    try {
        $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        $ptr2=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
        $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        $repeat=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr2)
        Require ($plain.Length -ge 12 -and $plain -ceq $repeat) 'Passwords differ or are shorter than 12 characters.'
        Require ($plain -notmatch '[\r\n]') 'Newlines are not supported in passwords.'
        $user=Get-AppIdentity
        $parts=$user.Split(':')
        # The password goes only via stdin to an ephemeral container; nothing
        # secret appears in shell history, Compose .env, or Docker inspect env.
        $payload=@("$name","$plain") -join "`n"
        $response=$payload | & docker compose --env-file .env -f compose.yaml run --rm --no-deps -T --entrypoint python odysseus /cpu-kit/admin_preseed.py $parts[0] $parts[1]
        Require ($LASTEXITCODE -eq 0) 'Admin provisioning failed. Your prior accounts were not intentionally changed.'
        Require ($response -match 'ADMIN_CREATED|EXISTING_AUTH_PRESERVED') 'Unexpected admin provisioning response.'
        if($response -match 'ADMIN_CREATED'){ Explain "First admin account created: $name" }
        else { Explain 'Admin account already exists; no changes made.' }
    } finally {
        $plain=$null; $repeat=$null; $payload=$null
        if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
        if($ptr2 -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2)}
    }
}
function Show-InstallStep([int]$Number,[string]$Description) { Write-Host "`n[$Number/6] $Description" -ForegroundColor Cyan }
function Install-Stack {
    Explain 'ZARZYSSEUS DOCKER — GUIDED INSTALL'
    Explain 'Shows every pull, service action, and readiness check. Existing named volumes, .env, and users are preserved.'
    Require (Confirm 'INSTALL' 'Install the Docker stack (Ollama, Odysseus, ChromaDB, SearXNG)? Downloads require disk space and network access.') 'Installation cancelled.'
    Show-InstallStep 1 'Docker Desktop engine and Compose'
    Check-Docker
    & docker info --format 'Engine: {{.ServerVersion}}'
    Show-InstallStep 2 'Configuration and existing services'
    Show-Network
    Show-Status
    Show-InstallStep 3 'Optional CPU model'
    Explain 'On slower machines, the 4B model may generate slowly.'
    if(Confirm 'PULL' 'Download Qwen3.5 4B CPU model and create its profile? This can take several GB.') {
        Start-Ollama
        Invoke-Compose @('exec','-T','cpu-ollama','ollama','pull','qwen3.5:4b-q4_K_M')
        Invoke-Compose @('exec','-T','cpu-ollama','ollama','create','qwen3.5-zarzysseus-cpu:4b','-f','/profiles/Modelfile.quality')
    } else { Explain 'Model pull skipped. Install from Ollama Management when ready.' }
    Show-InstallStep 4 'First admin account (before first Odysseus boot)'
    if(Confirm 'ACCOUNT' 'Set the first admin username/password now? Existing accounts are preserved.') {
        try { Setup-Admin } catch { Warn "First admin setup unavailable: $($_.Exception.Message). If needed, inspect first-run credentials in Docker logs." }
    } else { Explain 'Admin setup skipped. The upstream entrypoint may create a temporary password on first boot.' }
    Show-InstallStep 5 'Start Odysseus and supporting services'
    Start-App
    Show-Status
    Show-InstallStep 6 'Install the container agent/skills/MCP toolkit'
    try { Invoke-Bridge 'install'; Explain 'Toolkit bridge installed.' }
    catch { Warn "Toolkit installation needs attention: $($_.Exception.Message)" }
    Explain '--- INSTALL SUMMARY ---'
    Show-Network
    Show-Status
    Explain 'Running containers are not proof of inference readiness. Use Doctor to verify agents and models.'
}
function Show-ModelDoctor {
    Explain '=== MODEL VISIBILITY / OLLAMA DOCTOR (READ ONLY) ==='
    Explain '[1/3] Models in Docker Ollama:'
    Invoke-Compose @('exec','-T','cpu-ollama','ollama','list')
    Explain '[2/3] Ollama API as seen from Odysseus:'
    $probe=@'
import json,os,sys,urllib.request
url=os.getenv("OLLAMA_BASE_URL","http://cpu-ollama:11434").rstrip("/").removesuffix("/v1") + "/api/tags"
try:
    data=json.load(urllib.request.urlopen(url,timeout=8))
    models=[m.get("name","") for m in data.get("models",[]) if isinstance(m,dict)]
    print("OLLAMA_API_OK models="+str(len(models)))
    for model in models[:30]: print("  "+model)
except Exception as exc:
    print("OLLAMA_API_FAILED",type(exc).__name__,str(exc),file=sys.stderr)
    sys.exit(2)
'@
    Invoke-Compose @('exec','-T','odysseus','python','-c',$probe)
    Explain '[3/3] If the GUI is empty, sign in and refresh the Ollama provider/catalog.'
    Explain 'Docker endpoint: http://cpu-ollama:11434 (not localhost and not the published host port).'
    Explain 'Check existing provider/hidden/pinned model settings. No data was changed.'
}
function Show-Status {
    Explain "Docker hardware profile: $(Get-Profile) (Full is a feature policy, not automatic GPU activation)"
    Explain "Compose kit: $KitDir"
    Invoke-Compose @('--profile','app','ps')
}
function Show-Help {
    @'
Windows Docker: Docker Desktop running Linux containers, with the V11 CPU kit.
Commands: docker docker-prereq/docker-desktop-install, install/start/stop/restart/status/logs/down, model-setup quality|agent|moe,
models, model-doctor, ollama-start/stop, pull MODEL, toolkit-install, doctor, repair,
agent-doctor, agent-rollback, skills-doctor, skills-setup, mcp-health,
model-advisor, cookbook-fix status|progress, gpu-status,
network-status, network-configure, network-apply, auth-setup.
The Docker manager runs container-side repairs through the shared checksum-guarded
agent bridge. Native OS updates, drivers, Windows services, MLX and unrestricted
host file access are not supported inside containers. AMD RDNA3 GPU service
requires a compatible Linux ROCm host and is NOT available on Docker Desktop Windows.
'@ | Write-Host
}
function Install-DockerDesktop {
    Require (Confirm 'INSTALL' 'Install Docker Desktop with WinGet? This changes Windows software and may require administrator privileges, WSL 2 setup, and a reboot.') 'Docker Desktop install cancelled.'
    Require ([bool](Get-Command winget -ErrorAction SilentlyContinue)) 'WinGet is required. Install Docker Desktop manually from docker.com.'
    & winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
    Require ($LASTEXITCODE -eq 0) 'Docker Desktop installation failed or needs manual completion.'
    Explain 'Start Docker Desktop, choose Linux containers, finish WSL 2 initialization if prompted, and reopen Zarzysseus.'
}
function Show-DockerPrerequisites {
    Explain 'Windows Docker Desktop readiness:'
    try { Check-Docker; Write-Host 'PASS: Docker Desktop / Linux container engine and Compose available.' -ForegroundColor Green }
    catch { Warn $_.Exception.Message; Warn 'Choose Install Docker Desktop or start Docker Desktop with Linux containers.' }
}
function Dispatch([string]$What,[string]$Arg='',[string]$ExtraArg='') {
    switch($What.ToLowerInvariant()) {
        'tui' { Show-Menu; break }
        'help' { Show-Help; break }
        'docker-prereq' { Show-DockerPrerequisites; break }
        'docker-desktop-install' { Install-DockerDesktop; break }
        'profile' { Explain (Get-Profile); break }
        'install' { Install-Stack; break }
        'start' { Start-App; break }
        'stop' { Invoke-Compose @('--profile','app','stop'); break }
        'restart' { Invoke-Compose @('--profile','app','restart','odysseus'); break }
        'status' { Show-Status; break }
        'network-status' { Show-Network; break }
        'network-configure' { Set-Network; break }
        'network-apply' { Apply-Network; break }
        'auth-setup' { Setup-Admin; break }
        'logs' { Invoke-Compose @('--profile','app','logs','--tail','120','odysseus'); break }
        'down' { Require (Confirm 'DOWN' 'Stop and remove Compose containers? Named volumes and data will remain.') 'Cancelled.'; Invoke-Compose @('--profile','app','down'); break }
        'ollama-start' { Start-Ollama; break }
        'ollama-stop' { Invoke-Compose @('stop','cpu-ollama'); break }
        'models' { Invoke-Compose @('exec','-T','cpu-ollama','ollama','list'); break }
        'model-doctor' { Show-ModelDoctor; break }
        'pull' { Require ($Arg -match '^[\w./:-]+$') 'Provide a valid Ollama model ID'; Require (Confirm 'PULL' "Download Ollama model $Arg?") 'Cancelled.'; Start-Ollama; Invoke-Compose @('exec','-T','cpu-ollama','ollama','pull',$Arg); break }
        'model-setup' { Setup-Model $(if($Arg){$Arg}else{'quality'}); break }
        'toolkit-install' { Invoke-Bridge 'install'; break }
        'doctor' { Show-Status; Invoke-Agent 'container-agent-doctor'; break }
        'repair' {
            Require (Confirm 'REPAIR' 'Run the bundled Agent and tool recovery steps inside the Docker Odysseus container? These modify application files.') 'Cancelled.'
            foreach($r in @('agent-tool-focus-install','container-agent-repair','chat-continuity-fix','tool-json-fix')) { Invoke-Agent $r }
            Invoke-Compose @('restart','odysseus'); break
        }
        'gpu-status' { Warn 'On Windows Docker Desktop, the AMD RDNA3 /dev/kfd service is not supported. On a compatible Linux host, use Docker Full.'; break }
        {$_ -in @('system-update','accelerator-setup','vllm-install','sglang-install','mlx-install','sam-mask-install','uninstall','gpu-start','gpu-doctor','gpu-test')} {
            throw "Host-only or unsupported Windows Docker operation: $What. Use the native platform/compatible Linux runtime."
        }
        {$_ -in @('agent-doctor','agent-rollback','agent-tool-focus-install','container-agent-repair','chat-continuity-fix','tool-json-fix','cookbook-fix','mcp-health','mcp-setup','skills-doctor','skills-health','skills-list','skills-setup','skills-install','skills-search','skills-update','skills-sync-all','skills-runtime-fix','skills-mcp-fix','model-advisor','model-advisor-json','model-advisor-pins','providers','ollama-sync','tool-health','agent-smoke')} {
            $method=$What
            if($method -eq 'agent-doctor') {$method='container-agent-doctor'}
            $params=@(); if($Arg) {$params+=$Arg}; if($ExtraArg) {$params+=$ExtraArg}
            Invoke-Agent $method $params
            break
        }
        default { throw "Unknown Docker action '$What'. Run docker help." }
    }
}
function New-MenuEntry([string]$Label,[string]$Action,[string]$Argument='') {
    return @{Label=$Label; Action=$Action; Argument=$Argument}
}
function Show-Submenu([string]$Heading,[object[]]$Options) {
    while($true) {
        Write-Host "`n  $Heading" -ForegroundColor Cyan
        for($i=0;$i -lt $Options.Count;$i++) { Write-Host "  $($i+1). $($Options[$i].Label)" }
        Write-Host '  0. Back'
        $selected=Read-Host 'Choose'
        if($selected -eq '0'){ return }
        $i=0
        if(-not [int]::TryParse($selected,[ref]$i) -or $i -lt 1 -or $i -gt $Options.Count) { Warn 'Invalid selection.'; continue }
        $entry=$Options[$i-1]
        try { Dispatch $entry.Action $entry.Argument } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
    }
}
function Show-Menu {
    $categories=@(
        @{Title='INSTALL / UPDATE';Options=@((New-MenuEntry 'Check Docker Desktop readiness' 'docker-prereq'),(New-MenuEntry 'Install Docker Desktop (approval)' 'docker-desktop-install'),(New-MenuEntry 'Install CPU Docker stack' 'install'),(New-MenuEntry 'Install toolkit helper' 'toolkit-install'),(New-MenuEntry 'Status' 'status'))},
        @{Title='SERVICE MANAGEMENT';Options=@((New-MenuEntry 'Start Odysseus' 'start'),(New-MenuEntry 'Stop services' 'stop'),(New-MenuEntry 'Restart app' 'restart'),(New-MenuEntry 'Status' 'status'),(New-MenuEntry 'Logs' 'logs'),(New-MenuEntry 'Shut down Compose services' 'down'))},
        @{Title='MODEL RUNTIMES';Options=@((New-MenuEntry 'Ollama status' 'status'),(New-MenuEntry 'AMD RDNA3 GPU compatibility note' 'gpu-status'))},
        @{Title='MODEL MANAGER / HARDWARE FIT';Options=@((New-MenuEntry 'Diagnose model visibility' 'model-doctor'),(New-MenuEntry 'Installed models' 'models'),(New-MenuEntry 'Model advisor' 'model-advisor'))},
        @{Title='OLLAMA MANAGEMENT';Options=@((New-MenuEntry 'Install 4B CPU profile' 'model-setup' 'quality'),(New-MenuEntry 'Install 2.6B tool profile' 'model-setup' 'agent'),(New-MenuEntry 'List models' 'models'),(New-MenuEntry 'Start CPU Ollama' 'ollama-start'))},
        @{Title='MLX-LM MANAGEMENT';Options=@((New-MenuEntry 'Not supported in Windows Docker' 'mlx-install'))},
        @{Title='HUGGING FACE / MODEL FILES';Options=@((New-MenuEntry 'Model compatibility advisor' 'model-advisor'))},
        @{Title='SKILLS.SH / AGENT SKILLS';Options=@((New-MenuEntry 'Installed skills' 'skills-list'),(New-MenuEntry 'Skills health' 'skills-doctor'),(New-MenuEntry 'Approve skill setup' 'skills-setup'),(New-MenuEntry 'Skill model advisor' 'model-advisor'))},
        @{Title='MCP / FREEMCP';Options=@((New-MenuEntry 'MCP health' 'mcp-health'),(New-MenuEntry 'MCP setup' 'mcp-setup'))},
        @{Title='DIAGNOSTICS / TOOLS / ADVANCED';Options=@((New-MenuEntry 'Doctor' 'doctor'),(New-MenuEntry 'Agent repair (guarded)' 'repair'),(New-MenuEntry 'Cookbook status' 'cookbook-fix' 'status'),(New-MenuEntry 'Agent rollback' 'agent-rollback'))},
        @{Title='NETWORK DISCOVERABILITY';Options=@((New-MenuEntry 'Show binding / port / origins' 'network-status'),(New-MenuEntry 'Change local / LAN / Tailscale binding' 'network-configure'),(New-MenuEntry 'Apply saved binding (recreate app)' 'network-apply'),(New-MenuEntry 'First-run admin account setup' 'auth-setup'))}
    )
    while($true) {
        Write-Host "`n=========== ZARZYSSEUS / WINDOWS DOCKER $((Get-Profile).ToUpperInvariant()) ===========" -ForegroundColor Cyan
        for($i=0;$i -lt $categories.Count;$i++){ Write-Host ('{0,2} {1}' -f ($i+1), $categories[$i].Title) }
        Write-Host '12 Switch to Native Windows'
        Write-Host '13 Switch CPU-only / Full'
        Write-Host '0 Exit'
        $pick=Read-Host 'Choose'
        if($pick -eq '0') { return }
        if($pick -eq '12') {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MainScript mode native
            Write-Host 'Native mode saved. Reopen the launcher to enter Native mode.'
            return
        }
        if($pick -eq '13') {
            $next=if((Get-Profile) -eq 'cpu'){'full'}else{'cpu'}
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MainScript profile docker $next
            continue
        }
        $index=0
        if(-not [int]::TryParse($pick,[ref]$index) -or $index -lt 1 -or $index -gt $categories.Count) { Warn 'Invalid choice.'; continue }
        Show-Submenu $categories[$index-1].Title $categories[$index-1].Options
    }
}

try {
    Confirm-Kit
    Push-Location -LiteralPath $KitDir
    try {
        Dispatch $Action $Argument $Extra
    } finally { Pop-Location }
} catch {
    Write-Host "Zarzysseus Docker error: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
