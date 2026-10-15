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
function Install-Stack {
    Require (Confirm 'INSTALL' 'Install the CPU Docker stack (Ollama, Odysseus, ChromaDB, SearXNG)? Existing named volumes and .env will be retained.') 'Installation cancelled.'
    Start-App
    Explain 'The initial model is optional on a slower CPU. Select Model setup when ready.'
    try { Invoke-Bridge 'install' } catch { Warn "Toolkit not ready yet: $($_.Exception.Message). Use Toolkit Install after startup." }
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
models, ollama-start/stop, pull MODEL, toolkit-install, doctor, repair,
agent-doctor, agent-rollback, skills-doctor, skills-setup, mcp-health,
model-advisor, cookbook-fix status|progress, gpu-status.
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
        'logs' { Invoke-Compose @('--profile','app','logs','--tail','120','odysseus'); break }
        'down' { Require (Confirm 'DOWN' 'Stop and remove Compose containers? Named volumes and data will remain.') 'Cancelled.'; Invoke-Compose @('--profile','app','down'); break }
        'ollama-start' { Start-Ollama; break }
        'ollama-stop' { Invoke-Compose @('stop','cpu-ollama'); break }
        'models' { Invoke-Compose @('exec','-T','cpu-ollama','ollama','list'); break }
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
        @{Title='MODEL MANAGER / HARDWARE FIT';Options=@((New-MenuEntry 'Installed models' 'models'),(New-MenuEntry 'Model advisor' 'model-advisor'))},
        @{Title='OLLAMA MANAGEMENT';Options=@((New-MenuEntry 'Install 4B CPU profile' 'model-setup' 'quality'),(New-MenuEntry 'Install 2.6B tool profile' 'model-setup' 'agent'),(New-MenuEntry 'List models' 'models'),(New-MenuEntry 'Start CPU Ollama' 'ollama-start'))},
        @{Title='MLX-LM MANAGEMENT';Options=@((New-MenuEntry 'Not supported in Windows Docker' 'mlx-install'))},
        @{Title='HUGGING FACE / MODEL FILES';Options=@((New-MenuEntry 'Model compatibility advisor' 'model-advisor'))},
        @{Title='SKILLS.SH / AGENT SKILLS';Options=@((New-MenuEntry 'Installed skills' 'skills-list'),(New-MenuEntry 'Skills health' 'skills-doctor'),(New-MenuEntry 'Approve skill setup' 'skills-setup'),(New-MenuEntry 'Skill model advisor' 'model-advisor'))},
        @{Title='MCP / FREEMCP';Options=@((New-MenuEntry 'MCP health' 'mcp-health'),(New-MenuEntry 'MCP setup' 'mcp-setup'))},
        @{Title='DIAGNOSTICS / TOOLS / ADVANCED';Options=@((New-MenuEntry 'Doctor' 'doctor'),(New-MenuEntry 'Agent repair (guarded)' 'repair'),(New-MenuEntry 'Cookbook status' 'cookbook-fix' 'status'),(New-MenuEntry 'Agent rollback' 'agent-rollback'))},
        @{Title='NETWORK DISCOVERABILITY';Options=@((New-MenuEntry 'Show local binding' 'status'))}
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
