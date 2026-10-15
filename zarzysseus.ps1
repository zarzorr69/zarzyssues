#Requires -Version 5.1
<#
Zarzysseus: native Windows companion for the Odysseus Linux installer.
Use PowerShell 5.1+ (Windows 10/11). No WSL required for the core application.
Commands: tui, install, start, stop, restart, status, enable, disable,
repo-update, hf-token, hf-token-status, hf-token-clear, ollama-install,
ollama-start, ollama-pull, hf-pull, model-install, models, skills, skills-fix-all, accelerator-status,
network-mode localhost|lan|status, workspace-default [status],
chromadb-start, docker-setup, ollama-sync, tool-health, agent-doctor, agent-repair, agent-smoke, agent-rollback, chat-continuity-fix, cookbook-fix, mcp-setup, mcp-health, skills-mcp-fix, tool-json-fix, freemcp-setup, freemcp-status, freemcp-search, freemcp-login, agent-tool-focus-install.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Action = 'tui',
    [Parameter(Position=1)][string]$Argument = '',
    [Parameter(Position=2)][string]$Extra = ''
)
$ErrorActionPreference = 'Stop'
# V11.3 deployment router. Docker mode is evaluated before native Odysseus
# initialization, host Python/winget checks, or any native service repair.
$ZZModeDir=Join-Path $env:LOCALAPPDATA 'Zarzysseus'
$ZZModeFile=Join-Path $ZZModeDir 'deployment-mode.txt'
$ZZDockerPathFile=Join-Path $ZZModeDir 'docker-kit-path.txt'
function ZZ-Store([string]$File,[string]$Value) {
    New-Item -ItemType Directory -Force -Path $ZZModeDir | Out-Null
    [IO.File]::WriteAllText($File,$Value+"`n",([Text.UTF8Encoding]::new($false)))
}
function ZZ-Mode {
    if(Test-Path -LiteralPath $ZZModeFile) {
        $m=(Get-Content -LiteralPath $ZZModeFile -Raw).Trim().ToLowerInvariant()
        if($m -in @('native','docker')) { return $m }
    }
    return 'native'
}
function ZZ-Profile([string]$Platform) {
    $f=Join-Path $ZZModeDir "hardware-$Platform.txt"
    if(Test-Path -LiteralPath $f) {
        $v=(Get-Content -LiteralPath $f -Raw).Trim().ToLowerInvariant()
        if($v -in @('cpu','full')) { return $v }
    }
    if($Platform -eq 'docker') { return 'cpu' }
    return 'full'
}
function ZZ-DockerKit {
    $possible=@()
    if(Test-Path -LiteralPath $ZZDockerPathFile) {
        $possible+=((Get-Content -LiteralPath $ZZDockerPathFile -Raw).Trim())
    }
    $possible+=@( (Join-Path $PSScriptRoot 'docker'), (Join-Path $ZZModeDir 'source/zarzyssues-main/docker') )
    foreach($candidate in $possible) {
        if($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'zarzysseus-docker.ps1')) -and
           (Test-Path -LiteralPath (Join-Path $candidate 'compose.yaml'))) { return $candidate }
    }
    return ''
}
function ZZ-GetDockerKit {
    $kit=ZZ-DockerKit
    if($kit) { return $kit }
    Write-Host 'Docker mode requires the complete project (Windows script + docker/ directory).' -ForegroundColor Yellow
    if(-not [Environment]::UserInteractive -or (Read-Host 'Type DOWNLOAD to fetch the full GitHub source archive') -cne 'DOWNLOAD') {
        throw 'Docker kit not available. Download the full Zarzysseus release ZIP before running Docker mode.'
    }
    $location=Join-Path $ZZModeDir 'source'
    New-Item -ItemType Directory -Force -Path $location | Out-Null
    $archive=Join-Path $location 'main.zip'
    if(-not (Get-Command curl.exe -ErrorAction SilentlyContinue)){ throw 'curl.exe missing from Windows.' }
    & curl.exe -fL --retry 3 'https://github.com/zarzorr69/zarzyssues/archive/refs/heads/main.zip' -o $archive
    if($LASTEXITCODE -ne 0){ throw 'Unable to download the complete GitHub source archive.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $location -Force
    $kit=ZZ-DockerKit
    if(-not $kit){ throw 'Downloaded project does not contain the expected Windows Docker kit.' }
    return $kit
}
function ZZ-LaunchDocker([string]$What,[string]$Arg='',[string]$Arg2='') {
    $kit=ZZ-GetDockerKit
    & (Join-Path $kit 'zarzysseus-docker.ps1') -Action $What -Argument $Arg -Extra $Arg2
    if(-not $?) { throw "Windows Docker action $What failed." }
}
if($Action -eq 'tui' -and -not (Test-Path -LiteralPath $ZZModeFile) -and [Environment]::UserInteractive) {
    Write-Host "`n=== ZARZYSSEUS / WINDOWS FIRST START ===" -ForegroundColor Cyan
    Write-Host '1 Native Windows (PowerShell / local Odysseus)'
    Write-Host '2 Docker Desktop (isolated Linux containers)'
    $select=Read-Host 'Choose deployment [1/2]'
    if($select -eq '2') { ZZ-Store $ZZModeFile 'docker' }
    else { ZZ-Store $ZZModeFile 'native' }
}
if($Action -eq 'mode') {
    if($Argument -in @('docker','native')) {
        if($Argument -eq 'docker'){ $null=ZZ-GetDockerKit }
        ZZ-Store $ZZModeFile $Argument
        Write-Host "Saved Windows deployment: $Argument; no services were started or changed."
    } elseif($Argument -eq '' -or $Argument -eq 'status') {
        Write-Host "Windows deployment: $(ZZ-Mode); native hardware: $(ZZ-Profile native); Docker hardware: $(ZZ-Profile docker)"
    } else { throw 'Use mode native|docker|status.' }
    return
}
if($Action -eq 'docker-path') {
    if(-not $Argument -or -not (Test-Path -LiteralPath (Join-Path $Argument 'compose.yaml')) -or
       -not (Test-Path -LiteralPath (Join-Path $Argument 'zarzysseus-docker.ps1'))) {
        throw 'Specify the directory containing compose.yaml and zarzysseus-docker.ps1.'
    }
    ZZ-Store $ZZDockerPathFile ([IO.Path]::GetFullPath($Argument))
    Write-Host 'Windows Docker kit directory saved; existing .env and volumes are unchanged.'
    return
}
if($Action -eq 'profile') {
    if($Argument -eq '' -or $Argument -eq 'status') {
        Write-Host "Windows native: $(ZZ-Profile native); Docker: $(ZZ-Profile docker)"
    } else {
        if($Argument -notin @('docker','native') -or $Extra -notin @('cpu','full')) {
            throw 'Use profile docker|native cpu|full.'
        }
        ZZ-Store (Join-Path $ZZModeDir "hardware-$Argument.txt") $Extra
        Write-Host "Saved $Argument profile: $Extra. No model or service was restarted."
        if($Argument -eq 'native' -and $Extra -eq 'cpu') {
            Write-Host 'Native Windows CPU-only is advisory. Confirm your Ollama/driver device configuration separately.' -ForegroundColor Yellow
        }
    }
    return
}
if($Action -eq 'docker') {
    ZZ-LaunchDocker $(if($Argument){$Argument}else{'tui'}) $Extra
    return
}
if($Action -eq 'tui' -and (ZZ-Mode) -eq 'docker') {
    ZZ-LaunchDocker 'tui'
    return
}
# End deployment router. All previous Windows native commands remain intact.
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
# Docker installation is allowed only after a committed install/model selection, or explicit docker-setup.
# Read-only status and TUI browsing never install Docker.
$ChromaAutoStart = ($env:CHROMADB_AUTO_START -ne '0')
$DockerAutoInstall = ($env:ZARZYSSEUS_DOCKER_AUTO_INSTALL -ne '0')
$DefaultWorkspaceEnabled = ($env:ZARZYSSEUS_DEFAULT_WORKSPACE -ne '0')
$OllamaToolsEnabled = ($env:OLLAMA_SUPPORTS_TOOLS -ne '0')
$QwenFocusEnabled = ($env:ZARZYSSEUS_QWEN_TOOL_FOCUS -ne '0')
$McpAutoRepair = ($env:ZARZYSSEUS_MCP_AUTO_REPAIR -ne '0')
$FreeMcpAutoInstall = ($env:ZARZYSSEUS_FREEMCP_AUTO_INSTALL -ne '0')
$DirectToolJsonRecovery = ($env:ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY -ne '0')
$SkillMcpAutoInstall = ($env:ZARZYSSEUS_SKILL_MCP_AUTO_INSTALL -ne '0')
$FreeMcpRegistryRepo = if ($env:FREEMCP_REGISTRY_REPO) { $env:FREEMCP_REGISTRY_REPO } else { 'https://github.com/Appnova-EU-OU/awesome-remote-mcp-servers.git' }
$ChatContinuityGuard = ($env:ZARZYSSEUS_CHAT_CONTINUITY_GUARD -ne '0')
$CookbookFixesEnabled = ($env:ZARZYSSEUS_COOKBOOK_FIXES -ne '0')
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
                        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama'),
                        'C:\Program Files\Docker\Docker\resources\bin')) {
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
    if ($PSCommandPath -and ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($ManagedScript))) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $ManagedScript -Force
    }
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

# --- Odysseus integration repairs: first-use workspace, ChromaDB, Ollama tools ---
function Invoke-OdysseusPython([string]$Code, [string[]]$Arguments) {
    $py = Get-VenvPython
    if (-not (Test-Path -LiteralPath $py)) { Fail 'Odysseus Python environment not installed. Run install first.' }
    # A temporary script avoids Windows PowerShell 5.1 rewriting quotation marks
    # inside large multiline `python -c` arguments. No credentials are written.
    $temporaryScript = Join-Path $StateDir ("odysseus-integration-" + [guid]::NewGuid().ToString('N') + ".py")
    Set-Content -LiteralPath $temporaryScript -Value $Code -Encoding UTF8
    Push-Location $ProjectDir
    try {
        & $py $temporaryScript @Arguments
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { Fail "Odysseus integration check failed (Python exit $rc)." }
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $temporaryScript -Force -ErrorAction SilentlyContinue
    }
}
function Workspace-Default([switch]$Status) {
    $sourceFile = Join-Path $ProjectDir 'static\js\workspace.js'
    if ($Status) {
        Write-Host "Discovered checkout: $ProjectDir"
        if ((Test-Path -LiteralPath $sourceFile) -and
            (Select-String -LiteralPath $sourceFile -SimpleMatch 'ZARZYSSEUS_AGENT_WORKSPACE_DEFAULT_V1' -Quiet)) {
            Okay 'First-use Agent workspace patch installed (browser override preserved).'
        } else { Warn 'Default Agent workspace patch not installed.' }
        return
    }
    if (-not $DefaultWorkspaceEnabled) { Warn 'Default Agent workspace disabled by ZARZYSSEUS_DEFAULT_WORKSPACE=0'; return }
    if (-not (Is-Checkout $ProjectDir)) { Fail 'Clone/install Odysseus before setting a default workspace.' }
    if (-not (Test-Path -LiteralPath $sourceFile)) { Warn 'Upstream workspace.js missing; no source change made.'; return }
    $backup = Join-Path $ProjectDir 'data\local\patch-backups'
    $code = @'
import datetime
import json
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2]).expanduser().resolve(strict=True)
backup_dir = pathlib.Path(sys.argv[3])
if not project.is_dir() or project == project.parent:
    raise SystemExit("ERROR: unsafe or nonexistent project workspace")
original = source.read_text(encoding="utf-8")
marker = "// ZARZYSSEUS_AGENT_WORKSPACE_DEFAULT_V1"
start_anchor = "const API_BASE = window.location.origin;"
getter_original = """export function getWorkspace() {
  return Storage.get(KEYS.WORKSPACE, '') || '';
}"""
setter_original = """export function setWorkspace(path) {
  if (path) Storage.set(KEYS.WORKSPACE, path);
  else Storage.remove(KEYS.WORKSPACE);
  syncWorkspaceIndicator(path || '');
}"""
new_constant = (
    marker + "\n"
    + "const _ZARZYSSEUS_DEFAULT_WORKSPACE = " + json.dumps(str(project)) + ";\n"
    + "const _ZARZYSSEUS_WORKSPACE_CLEARED_KEY = 'zarzysseus.workspace.cleared';"
)
getter_new = """export function getWorkspace() {
  const selected = Storage.get(KEYS.WORKSPACE, '') || '';
  if (selected) return selected;
  // A deliberate click on Clear must not silently reactivate the default.
  if (Storage.get(_ZARZYSSEUS_WORKSPACE_CLEARED_KEY, '') === '1') return '';
  return _ZARZYSSEUS_DEFAULT_WORKSPACE;
}"""
setter_new = """export function setWorkspace(path) {
  if (path) {
    Storage.set(KEYS.WORKSPACE, path);
    Storage.remove(_ZARZYSSEUS_WORKSPACE_CLEARED_KEY);
  } else {
    Storage.remove(KEYS.WORKSPACE);
    Storage.set(_ZARZYSSEUS_WORKSPACE_CLEARED_KEY, '1');
  }
  syncWorkspaceIndicator(path || '');
}"""
if marker in original:
    declaration = re.compile(
        r"// ZARZYSSEUS_AGENT_WORKSPACE_DEFAULT_V1\n"
        r"const _ZARZYSSEUS_DEFAULT_WORKSPACE = [^\n]*;\n"
        r"const _ZARZYSSEUS_WORKSPACE_CLEARED_KEY = 'zarzysseus\.workspace\.cleared';"
    )
    if len(declaration.findall(original)) != 1 or getter_new not in original or setter_new not in original:
        print("    [warning] Existing workspace patch differs from expected version; source unchanged.")
        raise SystemExit(2)
    updated = declaration.sub(lambda _: new_constant, original, count=1)
else:
    if (original.count(start_anchor) != 1 or original.count(getter_original) != 1
            or original.count(setter_original) != 1):
        print("    [warning] Upstream workspace.js layout changed; source unchanged.")
        raise SystemExit(2)
    updated = original.replace(start_anchor, start_anchor + "\n" + new_constant, 1)
    updated = updated.replace(getter_original, getter_new, 1)
    updated = updated.replace(setter_original, setter_new, 1)
if updated == original:
    print(f"    [ready] Default Agent workspace: {project}")
    raise SystemExit(0)
backup_dir.mkdir(parents=True, exist_ok=True)
backup = backup_dir / ("workspace.js." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
backup.write_text(original, encoding="utf-8")
# Atomic replacement: preserve file permissions, avoid truncated JS on interruption.
import os
import tempfile
fd, temp = tempfile.mkstemp(prefix=".zarzysseus-workspace-", dir=str(source.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        out.write(updated)
    os.chmod(temp, source.stat().st_mode & 0o777)
    os.replace(temp, source)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print(f"    [configured] First-use Agent workspace: {project}")
print("    [note] Existing browser selection and explicit Clear remain respected.")
print(f"    [backup] {backup}")
'@
    Invoke-OdysseusPython $code @($sourceFile, $ProjectDir, $backup)
}
function Install-ChatContinuityFix([switch]$Status) {
    $sourceFile = Join-Path $ProjectDir 'routes\session_routes.py'
    if ($Status) {
        if ((Test-Path -LiteralPath $sourceFile) -and (Select-String -LiteralPath $sourceFile -SimpleMatch 'ZARZYSSEUS_CHAT_CONTINUITY_GUARD_V1' -Quiet)) { Okay 'Same-chat continuity guard installed.' }
        else { Warn 'Same-chat continuity guard not installed; upstream may already contain the fix.' }
        return
    }
    if (-not $ChatContinuityGuard) { Warn 'Chat continuity guard disabled by ZARZYSSEUS_CHAT_CONTINUITY_GUARD=0'; return }
    if (-not (Test-Path -LiteralPath $sourceFile)) { Warn 'session_routes.py missing; continuity patch skipped.'; return }
    $backup = Join-Path $ProjectDir 'data\local\patch-backups'
    $code = @'
from pathlib import Path
import datetime,re,sys,tempfile,os
path=Path(sys.argv[1]); backup_dir=Path(sys.argv[2]); marker='ZARZYSSEUS_CHAT_CONTINUITY_GUARD_V1'; text=path.read_text(encoding='utf-8')
if marker in text: print('    [ready] Same-chat continuity guard already installed'); raise SystemExit(0)
pat=re.compile(r"(?m)^(?P<i>[ \t]*)fire_event\(\s*['\"]session_created['\"]\s*,\s*user\s*\)\s*$")
m=pat.search(text)
if not m: print('    [note] Upstream session creation event layout changed or is already fixed; source unchanged'); raise SystemExit(0)
i=m.group('i'); replacement=f"{i}# {marker}\n{i}# Prevent immediate session-created housekeeping from deleting the active chat before turn two.\n{i}if False:\n{i}    fire_event('session_created', user)"
updated=text[:m.start()]+replacement+text[m.end():]; compile(updated,str(path),'exec')
backup_dir.mkdir(parents=True,exist_ok=True); backup=backup_dir/(path.name+'.'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.bak'); backup.write_text(text,encoding='utf-8')
fd,tmp=tempfile.mkstemp(prefix='.zar-chat-',dir=str(path.parent)); os.close(fd); Path(tmp).write_text(updated,encoding='utf-8'); os.replace(tmp,path); print(f'    [installed] Same-chat continuity guard; backup: {backup}')
'@
    Invoke-OdysseusPython $code @($sourceFile,$backup)
}
function Get-CookbookBridgeDir { return (Join-Path $ProjectDir 'data\local\cookbook-bin') }
# V10.1: guarded native HF cookbook routing. Does not install dependencies.
function Invoke-CookbookOneClickV10_1([string]$Mode = 'install') {
    $source = @'
#!/usr/bin/env python3
"""Zarzysseus V10.1 guarded Odysseus Cookbook source/runtime compatibility repair.

Targets verified existing upstream JS shapes. Does NOT install runtimes or infer fake GGUF
repositories. Applies files as one transaction with SHA-256 audited backups and rollback.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

MARKER = 'ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1'
FILES = ('static/js/cookbook.js', 'static/js/cookbookDownload.js', 'static/js/cookbook-hwfit.js')
MANIFEST = 'data/local/patch-backups/cookbook-native-routing-v10_1.json'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise ValueError(f'{label}: expected one known upstream anchor, found {count}; no files changed')
    return text.replace(old, new, 1)


def patch_core(text):
    # Keep true GGUF, Ollama, AWQ/GPTQ/FP8 etc. on their existing backends.
    # For plain HF repos with an estimated Q4 row but no GGUF source, download
    # native weights with vLLM (or SGLang on ROCm for general text models).
    # Voxtral Realtime is a supported vLLM realtime ASR model, not chat/GGUF.
    anchor = "  // GGUF → llama.cpp/Ollama-compatible.\n  if (isGgufLike) {"
    if anchor not in text:
        # Alternate upstream whitespace/ASCII comment variants are handled only
        # when the semantic anchor is unique and beside the known backend test.
        matches = list(re.finditer(r'(?m)^(\s*)// GGUF .*\n\1if \(isGgufLike\) \{', text))
        if len(matches) != 1:
            raise ValueError('cookbook.js backend selection differs from verified upstream; no changes')
        anchor = matches[0].group(0)
    insert = '''   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1:
   // A Q4_K_M *estimate* in hwfit is not evidence of GGUF weights. When
   // no actual GGUF source exists, pick native HF weights instead of sending
   // the user to Direct Download to guess a conversion repo.
   const _zarHasGgufSource = (Array.isArray(model.gguf_sources) && model.gguf_sources.some(s => !!s?.repo))
     || hasGgufFile;
   const _zarGgufRepo = /(?:^|[-_/\\s.])gguf(?:$|[-_/\\s.])/i.test(`${_nm} ${model.quant_repo || ''}`);
   const _zarHfRepo = /^[^\\s/]+\\/[^\\s/]+$/.test(String(model.name || ''));
   const _zarVoxtralRealtime = /(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(String(model.name || ''));
   if (_zarVoxtralRealtime) {
     return { backend: 'vllm', label: 'vLLM · speech (native)' };
   }
   if (isGgufLike && !model.is_gguf && !_zarHasGgufSource && !_zarGgufRepo && _zarHfRepo
       && /^(?:Q[2-8]|IQ[1-8])/.test(q)) {
     if (isRocm) return { backend: 'sglang', label: 'SGLang · native weights' };
     return { backend: 'vllm', label: 'vLLM · native weights' };
   }
'''
    text = replace_once(text, anchor, insert + anchor, 'cookbook.js backend decision')
    return text


def patch_download(text):
    anchor = "  const repo = backend === 'ollama'\n    ? (model.ollama || model.ollama_name || model.name)\n    : (ggufSource?.repo || model.quant_repo || model.name);"
    replacement = '''   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1: do not download an
   // imaginary quant repository for a native-weight HF model.
   const _zarNative = backend !== 'ollama' && backend !== 'llamacpp' && !!model._zarNativeOnly;
   const repo = backend === 'ollama'
     ? (model.ollama || model.ollama_name || model.name)
     : (_zarNative ? model.name : (ggufSource?.repo || model.quant_repo || model.name));'''
    return replace_once(text, anchor, replacement, 'cookbookDownload.js source choice')


def patch_hwfit(text):
    anchor = '''export function _hwfitRenderList(el, models) {
  if (!el) return;
  models = _sortHwfitRows(models);'''
    replacement = '''export function _hwfitRenderList(el, models) {
   if (!el) return;
   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1: fix catalog entries
   // that advertise Q4_K_M estimates for native BF16 ASR checkpoints.
   // This is a format correction, not a claim that vLLM is installed.
   models = (Array.isArray(models) ? models : []).map(m => {
     const name = String(m?.name || '');
     if (/(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(name)) {
       return { ...m, quant: 'BF16', quant_repo: null,
         required_gb: Math.max(Number(m.required_gb) || 0, 10.5),
         _zarNativeOnly: true };
     }
     const q = String(m?.quant || '').toUpperCase();
     const knownSource = !!m?.is_gguf
       || (Array.isArray(m?.gguf_sources) && m.gguf_sources.some(s => !!s?.repo))
       || (Array.isArray(m?.gguf_files) && m.gguf_files.some(f => /\\.gguf$/i.test(String(f?.rel_path || ''))));
     const namedGguf = /gguf/i.test(`${m?.quant_repo || ''} ${m?.repo_id || ''} ${name}`);
     if (!knownSource && !namedGguf && /^(?:Q[2-8]|IQ[1-8])/.test(q)
         && /^[^\\s/]+\\/[^\\s/]+$/.test(name)) {
       return { ...m, quant: 'native', quant_repo: null,
         required_gb: Math.max(Number(m.required_gb) || 0, (Number(m.params_b) || 0) * 2.2),
         _zarNativeOnly: true };
     }
     return m;
   });
   models = _sortHwfitRows(models);'''
    text = replace_once(text, anchor, replacement, 'cookbook-hwfit.js model listing')
    # Special-case ASR: no general text chat endpoint, and native runtime support is required.
    anchor = '''  if (modelData.is_image_gen) {
    html += `<div style="font-size:10px;opacity:0.5;margin-top:4px;">'''
    replacement = '''   if (/(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(String(modelData.name || ''))) {
     // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1
     html += `<div class="hwfit-panel-note">Native BF16 Arabic speech-to-text checkpoint (not a general chat LLM). Download uses the official Hugging Face repository; Run requires vLLM with realtime audio support and a compatible GPU/runtime. GPU memory fit alone does not prove runtime readiness.</div>`;
   } else if (modelData._zarNativeOnly) {
     html += `<div class="hwfit-panel-note">No GGUF source exists in this catalog entry. One-click Download uses the original native Hugging Face weights; Run requires a compatible native-serving backend. The catalog quantization estimate is not an actual GGUF file.</div>`;
   }
   if (modelData.is_image_gen) {
     html += `<div style="font-size:10px;opacity:0.5;margin-top:4px;">'''
    return replace_once(text, anchor, replacement, 'cookbook-hwfit.js runtime notice')

PATCHERS = dict(zip(FILES, (patch_core, patch_download, patch_hwfit)))


def atomic_write(path, raw):
    fd, temp = tempfile.mkstemp(prefix='.zar-cookbook-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(raw)
            out.flush()
            os.fsync(out.fileno())
        shutil.copymode(path, temp)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def install(project):
    manifest = project / MANIFEST
    if manifest.exists():
        return status(project)
    original = {}
    patches = {}
    for rel in FILES:
        path = project / rel
        if not path.is_file():
            raise ValueError(f'missing Cookbook file: {path} (no changes)')
        raw = path.read_bytes()
        text = raw.decode('utf-8')
        if MARKER in text:
            raise ValueError(f'{rel} already contains patch but manifest missing; refusing overwrite')
        patched = PATCHERS[rel](text).encode('utf-8')
        if patched == raw or MARKER not in patched.decode('utf-8'):
            raise ValueError(f'{rel} failed required transformation (no changes)')
        original[rel] = raw
        patches[rel] = patched
    # Pre-validated all files before any mutation. Backups are private and
    # written before source changes. Manifest digest controls rollback.
    backup_dir = manifest.parent / 'cookbook-native-v10_1'
    backup_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for rel in FILES:
        backup = backup_dir / Path(rel).name
        if backup.exists() and backup.read_bytes() != original[rel]:
            raise ValueError(f'existing backup collision: {backup}')
        backup.write_bytes(original[rel])
        records.append(dict(file=rel, before=digest(original[rel]), after=digest(patches[rel]), backup=str(backup.relative_to(project))))
    applied = []
    try:
        for rel in FILES:
            atomic_write(project / rel, patches[rel])
            applied.append(rel)
        manifest.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix='.zar-cb-manifest-', dir=str(manifest.parent))
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            json.dump(dict(version='V10.1', marker=MARKER, files=records), out, indent=2)
        os.replace(temp, manifest)
    except Exception:
        for rel in reversed(applied):
            atomic_write(project / rel, original[rel])
        raise
    print('Cookbook V10.1: installed; corrected catalog source/runtime routing and native-weight download.')
    print(f'Backup manifest: {manifest}')
    return 0


def status(project):
    manifest = project / MANIFEST
    if not manifest.exists():
        print('Cookbook V10.1: not installed')
        return 2
    record = json.loads(manifest.read_text(encoding='utf-8'))
    valid = True
    for item in record['files']:
        p = project / item['file']
        good = p.is_file() and digest(p.read_bytes()) == item['after']
        print(f"{'OK' if good else 'CHANGED'}: {item['file']}")
        valid &= good
    return 0 if valid else 3


def rollback(project):
    manifest = project / MANIFEST
    if not manifest.is_file():
        raise ValueError('not installed; no rollback manifest')
    data = json.loads(manifest.read_text(encoding='utf-8'))
    for entry in data['files']:
        path = project / entry['file']
        backup = project / entry['backup']
        if not path.is_file() or digest(path.read_bytes()) != entry['after']:
            raise ValueError(f'{path} modified since repair; refusing unsafe rollback')
        if not backup.is_file() or digest(backup.read_bytes()) != entry['before']:
            raise ValueError(f'{backup} missing or altered; refusing rollback')
    for entry in data['files']:
        atomic_write(project / entry['file'], (project / entry['backup']).read_bytes())
    manifest.unlink()
    print('Cookbook V10.1: safely rolled back to original verified sources.')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=('install', 'status', 'rollback'))
    ap.add_argument('--project', type=Path, required=True)
    args = ap.parse_args()
    project = args.project.expanduser().resolve()
    if not project.is_dir():
        ap.error(f'missing Odysseus checkout: {project}')
    try:
        return {'install':install, 'status':status, 'rollback':rollback}[args.action](project)
    except (ValueError, OSError, UnicodeError, KeyError) as ex:
        print(f'Cookbook V10.1: {ex}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
'@
    $path = Join-Path $ProjectDir 'data\local\zarzysseus_cookbook_oneclick_v10_1.py'
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $source + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
    & $python $path $Mode --project $ProjectDir
    if ($LASTEXITCODE -ne 0) { throw "Cookbook V10.1 $Mode failed (exit $LASTEXITCODE). Existing source may be newer; inspect the output before retrying." }
}

# V10.2 guarded progress UI repair, no backend/model changes.
function Invoke-CookbookProgressV10_2([string]$Mode = 'install') {
    $source = @'
#!/usr/bin/env python3
"""V10.2: guarded Cookbook task progress UI repair. Affects display/polling only.

Installs into Odysseus static/js/cookbookRunning.js with SHA256 backups. No
backend/model/download command changes. Does not depend on runtime network.
"""
import argparse, hashlib, json, os, pathlib, tempfile, sys
P='static/js/cookbookRunning.js'
M='data/local/patch-backups/cookbook-progress-v10_2.json'
MARKER='ZARZYSSEUS_COOKBOOK_PROGRESS_V10_2'

def sha(data):return hashlib.sha256(data).hexdigest()
def change(t,old,new,label):
    n=t.count(old)
    if n!=1:raise ValueError(f'{label}: upstream anchor count {n}, expected 1; no changes made')
    return t.replace(old,new,1)

# Inserted in module scope. Renders a compact bar even if the raw tmux logs are
# hidden; reports count-based progress distinctly from aggregate transfer bytes.
JS=r'''
// ZARZYSSEUS_COOKBOOK_PROGRESS_V10_2 — private UI only; no backend changes.
const _zarDlStyleId = 'zar-cookbook-download-progress-v10-2';
function _zarDlStyle() {
  if (document.getElementById(_zarDlStyleId)) return;
  const css = document.createElement('style'); css.id = _zarDlStyleId;
  css.textContent = `
    .zar-dl-card {padding:12px 12px 11px;display:grid;gap:7px;border-top:1px solid rgba(160,180,200,.1)}
    .zar-dl-line{display:flex;justify-content:space-between;gap:8px;align-items:baseline;font-size:12px;color:var(--fg-muted,#9da7b4)}
    .zar-dl-title{color:var(--fg,#e8eaf0);font-weight:600}
    .zar-dl-track{width:100%;height:9px;border-radius:999px;overflow:hidden;background:rgba(150,165,180,.17)}
    .zar-dl-fill{height:100%;width:0;background:linear-gradient(90deg,#49a2ff,#4bd6a0);border-radius:999px;transition:width .35s ease}
    .zar-dl-card[data-indeterminate="true"] .zar-dl-fill{width:30%;animation:zar-dl-move 1.4s ease-in-out infinite alternate}
    .zar-dl-card[data-state="done"] .zar-dl-fill{background:#50c878;animation:none;width:100%}
    .zar-dl-card[data-state="error"] .zar-dl-fill{background:#f26d6d;animation:none}
    .zar-dl-logs{background:none;border:0;padding:0;text-align:left;color:var(--accent,#70bfff);font-size:11px;cursor:pointer;width:max-content}
    .zar-dl-logs:hover{text-decoration:underline}
    @keyframes zar-dl-move{from{transform:translateX(0)}to{transform:translateX(230%)}}
    @media (prefers-reduced-motion:reduce){.zar-dl-fill{transition:none!important;animation:none!important}}
  `; document.head.appendChild(css);
}
function _zarDlParse(raw) {
  const lines = String(raw || '').replace(/\x1b\[[0-9;]*[A-Za-z]/g,'').replace(/\r/g,'\n');
  // Aggregate byte progress (HF Hub/hf_transfer). Prefer this over shard %.
  const bytes = [...lines.matchAll(/Downloading\s*\(incomplete[^)]*\):\s*(\d{1,3})%/ig)];
  const files = [...lines.matchAll(/Fetching\s+(\d+)\s+files:\s*(\d{1,3})%/ig)];
  if (bytes.length) return { percent: Math.min(100,+bytes[bytes.length-1][1]), stage:'Transferring model weights', unit:'bytes' };
  // HF aggregates finished files; this is not a byte-based percentage.
  if (files.length) {
    const x=files[files.length-1]; const pct=Math.min(100,+x[2]);
    return {percent:pct, stage:`Downloading · ${x[1]} files`,unit:'files'};
  }
  const done = lines.includes('DOWNLOAD_OK');
  if (done) return {percent:100,stage:'Download complete',unit:'complete'};
  if (/Reconstructing\s*\(incomplete|Reconstructing/i.test(lines)) return {percent:null,stage:'Verifying downloaded files',unit:'phase'};
  if (/Downloading bytes:/i.test(lines)) return {percent:null,stage:'Transferring model weights',unit:'phase'};
  if (/Downloading|Fetching|FILE\s+/i.test(lines)) return {percent:null,stage:'Downloading model files',unit:'phase'};
  return {percent:null,stage:'Connecting to download source',unit:'phase'};
}
function _zarDlSync(el, task, raw) {
  if (!el || task?.type !== 'download') return;
  _zarDlStyle();
  let card=el.querySelector('.zar-dl-card');
  if (!card) {
    card=document.createElement('div'); card.className='zar-dl-card';
    card.innerHTML=`<div class="zar-dl-line"><span class="zar-dl-title"></span><span class="zar-dl-pct"></span></div>
      <div class="zar-dl-track" role="progressbar" aria-label="Model download progress"><div class="zar-dl-fill"></div></div>
      <button class="zar-dl-logs" type="button">Show logs</button>`;
    const log=el.querySelector('.cookbook-output-wrap');
    if (log) log.parentNode.insertBefore(card,log); else el.appendChild(card);
    card.querySelector('.zar-dl-logs').addEventListener('click',e=>{
      e.stopPropagation();el.querySelector('.cookbook-task-header')?.click();
      const hidden=el.querySelector('.cookbook-output-wrap')?.classList.contains('cookbook-task-collapsed');
      card.querySelector('.zar-dl-logs').textContent=hidden?'Show logs':'Hide logs';
    });
  }
  const status=task.status || el.dataset.status || 'running';
  const failed=['error','failed','crashed','stopped'].includes(status);
  const complete=['done','completed'].includes(status);
  const p=_zarDlParse(raw);
  let pct = complete ? 100 : p.percent;
  if (pct != null && !complete && !failed) {
    // A resumed download may print older and newer snapshots together; don't
    // decrease the displayed value within the same task card.
    pct=Math.max(pct,Number(card.dataset.lastPct || 0));
    card.dataset.lastPct=String(pct);
  }
  card.dataset.state=failed?'error':(complete?'done':'running');
  card.dataset.indeterminate=String(pct===null && !complete && !failed);
  const heading=failed?'Download stopped':complete?'Download complete':status==='queued'?'Queued':p.stage;
  card.querySelector('.zar-dl-title').textContent=heading;
  card.querySelector('.zar-dl-pct').textContent=complete?'100%':(failed?'':(pct!==null?`${pct}%${p.unit==='files'?' of files':''}`:'Working…'));
  const bar=card.querySelector('.zar-dl-track');
  const fill=card.querySelector('.zar-dl-fill');
  fill.style.width=pct!==null?`${pct}%`:'';
  if(pct!==null)bar.setAttribute('aria-valuenow',String(pct));else bar.removeAttribute('aria-valuenow');
  bar.setAttribute('aria-valuetext',heading);
  card.querySelector('.zar-dl-logs').textContent=el.querySelector('.cookbook-output-wrap')?.classList.contains('cookbook-task-collapsed')?'Show logs':'Hide logs';
}
'''


def change_line(t, line, added, label):
    # A complete line is a safer, version-tolerant anchor than a fixed count of
    # leading spaces. Refuse ambiguous or absent matches; preserve indentation.
    import re
    matches = list(re.finditer(r'(?m)^([ \t]*)' + re.escape(line) + r'$', t))
    if len(matches) != 1:
        raise ValueError(f'{label}: upstream anchor count {len(matches)}, expected 1; no changes made')
    match = matches[0]
    indent = match.group(1)
    return t[:match.start()] + indent + added + '\n' + indent + line + t[match.end():]

def patch(t):
    if MARKER in t:raise ValueError('patch marker already present without verified manifest')
    t=change(t,'function _downloadBadgeText(progress) {',JS+'\nfunction _downloadBadgeText(progress) {','helper insertion')
    t=change(t,"      const terminalDiag = _terminalServeDiagnosis(task, el.querySelector('.cookbook-output-pre')?.textContent || task.output || '');",
        "      _zarDlSync(el, task, task.output || el.querySelector('.cookbook-output-pre')?.textContent || '');\n      const terminalDiag = _terminalServeDiagnosis(task, el.querySelector('.cookbook-output-pre')?.textContent || task.output || '');",'existing card update')
    t=change_line(t,"const _waveEl = el.querySelector('.cookbook-task-wave');",
        "_zarDlSync(el, task, task.output || '');",'new card update')
    t=change(t,"(_mobileCollapseDefault && !_shouldAutoExpandTaskOutput(task)) ? ' cookbook-task-collapsed' : ''",
        "(task.type === 'download' ? !_expandedTaskIds.has(task.sessionId) : (_mobileCollapseDefault && !_shouldAutoExpandTaskOutput(task))) ? ' cookbook-task-collapsed' : ''",'default download log collapse')
    t=change(t,"    const _streamExpanded = _wrapForStream && !_wrapForStream.classList.contains('cookbook-task-collapsed');",
        "    const _streamExpanded = task.type === 'download' || (_wrapForStream && !_wrapForStream.classList.contains('cookbook-task-collapsed'));",'polling initial')
    t=change(t,"  if (!_isRunningTabVisible() || !wrap || wrap.classList.contains('cookbook-task-collapsed')) return;",
        "  if (!_isRunningTabVisible() || !wrap || (task.type !== 'download' && wrap.classList.contains('cookbook-task-collapsed'))) return;",'polling start')
    t=change(t,"    if (!el.isConnected || !_isRunningTabVisible() || !liveWrap || liveWrap.classList.contains('cookbook-task-collapsed')) {",
        "    if (!el.isConnected || !_isRunningTabVisible() || !liveWrap || (task.type !== 'download' && liveWrap.classList.contains('cookbook-task-collapsed'))) {",'polling while closed')
    t=change(t,"        output.textContent = snapshot;",
        "        output.textContent = snapshot;\n        _zarDlSync(el, task, snapshot);",'polling refresh')
    # Closing the raw console must not abort a DOWNLOAD's progress polling.
    t=change(t,"        if (el._abort) {\n          try { el._abort.abort(); } catch {}\n          el._abort = null;\n        }",
        "        if (task.type !== 'download' && el._abort) {\n          try { el._abort.abort(); } catch {}\n          el._abort = null;\n        }",'log close behavior')
    return t

def atomic(path,raw):
    fd,tmp=tempfile.mkstemp(prefix='.zar-cb-progress-',dir=str(path.parent))
    try:
        with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
        os.chmod(tmp,path.stat().st_mode);os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def run(project,action):
    path=project/P; manifest=project/M
    if action=='status':
        if not manifest.exists():print('Cookbook compact progress V10.2: not installed');return 2
        record=json.loads(manifest.read_text()); matched=path.is_file() and sha(path.read_bytes())==record['after'];
        print('Cookbook compact progress V10.2:', 'INSTALLED' if matched else 'CHANGED; review before overwrite'); return 0 if matched else 3
    if action=='install':
        if manifest.exists():return run(project,'status')
        if not path.is_file():raise ValueError(f'missing {path}')
        old=path.read_bytes();new=patch(old.decode('utf-8')).encode('utf-8')
        backup=manifest.parent/'cookbook-progress-v10_2.before.js';backup.parent.mkdir(parents=True,exist_ok=True)
        if backup.exists() and backup.read_bytes()!=old:raise ValueError('backup conflict; refusing overwrite')
        backup.write_bytes(old)
        atomic(path,new)
        manifest.write_text(json.dumps({'version':'V10.2','file':P,'before':sha(old),'after':sha(new),'backup':str(backup.relative_to(project))},indent=2)+'\n')
        print('Cookbook V10.2: compact live download bars installed; raw logs available on demand; no download commands modified.')
        return 0
    if action=='rollback':
        if not manifest.is_file():raise ValueError('not installed')
        record=json.loads(manifest.read_text());back=project/record['backup']
        if not path.is_file() or sha(path.read_bytes())!=record['after']:raise ValueError('current source differs from V10.2; refusing overwrite')
        if not back.is_file() or sha(back.read_bytes())!=record['before']:raise ValueError('backup changed; refusing rollback')
        atomic(path,back.read_bytes());manifest.unlink();print('Cookbook V10.2: restored original progress UI');return 0
    raise ValueError('unknown mode')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['install','status','rollback']);ap.add_argument('--project',type=pathlib.Path,required=True)
    a=ap.parse_args()
    try:sys.exit(run(a.project.resolve(),a.action))
    except (OSError,ValueError,UnicodeError,KeyError) as ex:print(f'Cookbook V10.2: {ex}',file=sys.stderr);sys.exit(1)
'@
    $path = Join-Path $ProjectDir 'data\local\zarzysseus_cookbook_progress_v10_2.py'
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $source + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
    & $python $path $Mode --project $ProjectDir
    if ($LASTEXITCODE -ne 0) { throw "Cookbook V10.2 $Mode failed ($LASTEXITCODE); inspect output" }
}

# V11.6: protected Ollama Cookbook download -> chat model picker bridge.
function Invoke-CookbookAutoAddV11_6([string]$Mode = 'install') {
    if ($Mode -notin @('install','status','rollback')) { throw 'Expected install, status, or rollback.' }
    $source = @'
#!/usr/bin/env python3
"""Guarded V11.6 Cookbook Ollama download -> model picker refresh.

Does not download, serve, or switch models. Only reconciles completed,
local Ollama downloads that the Odysseus server can verify.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

MARKER = "ZARZYSSEUS_COOKBOOK_OLLAMA_AUTOADD_V11_6"
TARGET = "static/js/cookbookRunning.js"
MANIFEST = "data/local/patch-backups/cookbook-ollama-autoadd-v11_6.json"
BACKUP = "data/local/patch-backups/cookbook-ollama-autoadd-v11_6.before.js"
ANCHOR = """function _updateTask(sessionId, updates) {
  const tasks = _loadTasks();
  const task = tasks.find(t => t.sessionId === sessionId);
  if (task) {
    Object.assign(task, updates);
    _saveTasks(tasks);
  }
"""

INSERT = r'''// ZARZYSSEUS_COOKBOOK_OLLAMA_AUTOADD_V11_6
// Only verified Ollama downloads become chat-picker entries. Downloading a
// generic HF checkpoint does not make it a text-generation model.
const _zarAutoAddedSessions = new Set();
async function _zarReconcileOllamaDownload(task) {
  if (!task || task.type !== 'download' || task.payload?.backend !== 'ollama') return;
  // The app's /api/runtime describes *its own* endpoint, not an arbitrary SSH
  // server. Never register a remote model as if it were installed locally.
  if (task.remoteHost || task.payload?.remote_host) return;
  const model = String(task.payload?.repo_id || '').trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,180}$/.test(model)) return;
  const id = String(task.sessionId || '');
  if (!id || _zarAutoAddedSessions.has(id)) return;
  _zarAutoAddedSessions.add(id);
  try {
    const rr = await fetch('/api/runtime', { credentials: 'same-origin' });
    if (!rr.ok) throw Error(`Runtime configuration unavailable (${rr.status})`);
    const runtime = await rr.json();
    const base = String(runtime?.ollama_base_url || (!runtime?.in_docker ? 'http://127.0.0.1:11434/v1' : '')).trim();
    if (!base) throw Error('Ollama endpoint is not configured in Odysseus');
    const parsed = new URL(base);
    if (!['http:', 'https:'].includes(parsed.protocol)) throw Error('Invalid Ollama endpoint');
    // The address comes from Odysseus server configuration. The browser never
    // connects to it; Odysseus's admin-only endpoint test makes the request.
    const form = new FormData();
    form.set('base_url', base);
    form.set('endpoint_kind', 'local');
    const check = await fetch('/api/model-endpoints/test', {
      method: 'POST', credentials: 'same-origin', body: form,
    });
    if (!check.ok) throw Error(`Ollama verification failed (${check.status})`);
    const result = await check.json();
    const found = Array.isArray(result?.models) ? result.models.map(x => String(x).toLowerCase()) : [];
    const expected = model.toLowerCase();
    const isFound = found.includes(expected) || (expected.endsWith(':latest')
      ? found.includes(expected.slice(0, -7)) : found.includes(expected + ':latest'));
    if (!isFound) throw Error(`Ollama does not list ${model}; download may not be complete`);
    const fields = new FormData();
    fields.set('name', 'Ollama (Local)');
    fields.set('base_url', base);
    fields.set('model_type', 'llm');
    fields.set('endpoint_kind', 'local');
    fields.set('require_models', 'true');
    // An explicit pin permits the selected model to appear even if a prior
    // endpoint has an allowlist; the API merges it without clearing old pins.
    fields.set('pinned_models', JSON.stringify([model]));
    const added = await fetch('/api/model-endpoints', {
      method: 'POST', credentials: 'same-origin', body: fields,
    });
    if (!added.ok) throw Error(`Could not register Ollama endpoint (${added.status})`);
    if (window.modelsModule?.refreshModels) {
      await window.modelsModule.refreshModels(true, { waitForRefresh: true });
    } else {
      const refreshed = await fetch('/api/models?refresh=true&wait_refresh=true', { credentials: 'same-origin' });
      if (!refreshed.ok) throw Error(`Model catalog refresh failed (${refreshed.status})`);
    }
    uiModule.showToast(`${model} is available in the model picker; select it when ready.`);
  } catch (error) {
    uiModule.showToast(`Ollama download finished, but picker sync needs attention: ${error.message}`, 9000);
  }
}
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-cookbook-autoadd-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, path.stat().st_mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def transform(text: str) -> str:
    if MARKER in text:
        raise ValueError('Patch marker already present but no manifest; refusing unsafe overwrite')
    if text.count(ANCHOR) != 1:
        raise ValueError(f'Cookbook task update layout changed (anchor count {text.count(ANCHOR)}); source unchanged')
    updated = text.replace(
        ANCHOR, INSERT + '\n' + ANCHOR.replace('    _saveTasks(tasks);\n',
           "    _saveTasks(tasks);\n    if (updates.status === 'done') {\n      void _zarReconcileOllamaDownload(task);\n    }\n"), 1
    )
    assert updated.count(MARKER) == 1
    return updated


def status(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    if not manifest.is_file():
        print('Cookbook Ollama auto-add V11.6: not installed')
        return 2
    record = json.loads(manifest.read_text())
    ok = file.exists() and sha(file.read_bytes()) == record['after']
    print('Cookbook Ollama auto-add V11.6:', 'INSTALLED' if ok else 'CHANGED; review manually')
    return 0 if ok else 3


def install(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    backup = root / BACKUP
    if manifest.exists():
        return status(root)
    if not file.is_file():
        raise ValueError(f'{file} missing; no changes')
    before = file.read_bytes()
    after = transform(before.decode('utf-8')).encode('utf-8')
    # Never overwrite an existing earlier backup if its contents differ.
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists() and backup.read_bytes() != before:
        raise ValueError(f'Existing backup differs: {backup}; source unchanged')
    if not backup.exists():
        fd, temp = tempfile.mkstemp(dir=str(backup.parent), prefix='.zar-cb-backup-')
        with os.fdopen(fd, 'wb') as f:
            f.write(before)
        os.replace(temp, backup)
    atomic_write(file, after)
    record = dict(marker=MARKER, file=TARGET, backup=BACKUP, before=sha(before), after=sha(after))
    fd, temp = tempfile.mkstemp(dir=str(manifest.parent), prefix='.zar-cb-manifest-')
    with os.fdopen(fd, 'w') as f:
        json.dump(record, f, indent=2)
    os.replace(temp, manifest)
    print('Cookbook V11.6: verified Ollama downloads now refresh the chat model picker.')
    print('Only local Ollama models are auto-added; HF files never masquerade as chat servers.')
    return 0


def rollback(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    if not manifest.is_file():
        raise ValueError('Patch not installed')
    record = json.loads(manifest.read_text())
    backup = root / record['backup']
    if record['marker'] != MARKER or record['file'] != TARGET:
        raise ValueError('Unexpected manifest; refusing rollback')
    if sha(file.read_bytes()) != record['after'] or sha(backup.read_bytes()) != record['before']:
        raise ValueError('Installed file or backup changed; refusing rollback')
    atomic_write(file, backup.read_bytes())
    manifest.unlink()
    print('Cookbook V11.6: original task UI restored')
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=('install', 'status', 'rollback'))
    p.add_argument('--project', type=Path, required=True)
    a = p.parse_args()
    try:
        return {'install': install, 'status': status, 'rollback': rollback}[a.action](a.project)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print(f'Cookbook V11.6: {exc}', file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

'@
    $path = Join-Path $ProjectDir 'data\local\zarzysseus_cookbook_autoadd_v11_6.py'
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $source, (New-Object System.Text.UTF8Encoding($false)))
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
    & $python $path $Mode --project $ProjectDir
    if ($LASTEXITCODE -ne 0) { throw "Cookbook auto-add V11.6 $Mode failed ($LASTEXITCODE); inspect output" }
}

function Install-CookbookFixes([switch]$Status) {
    $bridge = Get-CookbookBridgeDir
    $route = Join-Path $ProjectDir 'routes\cookbook_routes.py'
    if ($Status) {
        if (Test-Path -LiteralPath (Join-Path $bridge 'hf.cmd')) { Okay 'Cookbook HF retry bridge installed.' } else { Warn 'Cookbook HF retry bridge not installed.' }
        if ((Test-Path -LiteralPath $route) -and (Select-String -LiteralPath $route -SimpleMatch 'ZARZYSSEUS_COOKBOOK_DOWNLOAD_STATUS_V1' -Quiet)) { Okay 'Cookbook DOWNLOAD_OK status guard installed.' } else { Write-Host 'Cookbook DOWNLOAD_OK status guard: upstream-fixed / not installed' }
        Write-Host 'Cookbook repair path never runs a full Windows OS update.'
        try { Invoke-CookbookOneClickV10_1 -Mode 'status' } catch { Warn $_.Exception.Message }
        try { Invoke-CookbookProgressV10_2 -Mode 'status' } catch { Warn $_.Exception.Message }
        try { Invoke-CookbookAutoAddV11_6 -Mode 'status' } catch { Warn $_.Exception.Message }
        return
    }
    if (-not $CookbookFixesEnabled) { Warn 'Cookbook fixes disabled by ZARZYSSEUS_COOKBOOK_FIXES=0'; return }
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { Fail 'Install the Odysseus stack before Cookbook repair.' }
    $hf = Join-Path (Split-Path -Parent $python) 'hf.exe'
    if (-not (Test-Path -LiteralPath $hf)) { Invoke-Checked $python @('-m','pip','install','-U','huggingface_hub[cli]') }
    New-Item -ItemType Directory -Force -Path $bridge | Out-Null
    $hf = Join-Path (Split-Path -Parent $python) 'hf.exe'
    $cmd = @"
@echo off
setlocal
set "REAL_HF=$hf"
if /I not "%~1"=="download" goto passthrough
for /L %%A in (1,1,10) do (
  call "%REAL_HF%" %*
  if not errorlevel 1 exit /b 0
  echo [zarzysseus-cookbook] hf download attempt %%A failed; retrying resumably 1>&2
  if not %%A==10 timeout /t 15 /nobreak >nul
)
exit /b 1
:passthrough
"%REAL_HF%" %*
exit /b %errorlevel%
"@
    Set-Content -LiteralPath (Join-Path $bridge 'hf.cmd') -Value $cmd -Encoding ASCII
    Okay "Cookbook HF retry bridge: $bridge\hf.cmd"
    if (Test-Path -LiteralPath $route) {
        $backup = Join-Path $ProjectDir 'data\local\patch-backups'
        $code = @'
from pathlib import Path
import datetime,re,sys,tempfile,os
path=Path(sys.argv[1]); backup_dir=Path(sys.argv[2]); marker='ZARZYSSEUS_COOKBOOK_DOWNLOAD_STATUS_V1'; text=path.read_text(encoding='utf-8')
if marker in text: print('    [ready] Cookbook DOWNLOAD_OK status guard already installed'); raise SystemExit(0)
start=text.find('def _cookbook_tasks_status_sync')
if start<0 or 'download_has_ok' not in text[start:]: print('    [note] Cookbook status layout differs or upstream is already fixed; source unchanged'); raise SystemExit(0)
mnext=re.search(r'(?m)^def\s+',text[start+5:]); end=start+5+mnext.start() if mnext else len(text); block=text[start:end]
out=[]; changed=0; marked=False
for line in block.splitlines(True):
    stripped=line.lstrip(); indent=line[:len(line)-len(stripped)]; target=None
    if '_download_cache_complete(' in stripped and (stripped.startswith('if ') or stripped.startswith('elif ')) and 'download_has_ok' not in stripped: target='download_has_ok'
    elif '_download_cache_incomplete(' in stripped and (stripped.startswith('if ') or stripped.startswith('elif ')) and 'download_has_failed' not in stripped: target='download_has_failed'
    if target:
        if not marked: out.append(indent+'# '+marker+' — trust conclusive runner markers before cache probes.\n'); marked=True
        stripped=('if '+target+' or '+stripped[3:]) if stripped.startswith('if ') else ('elif '+target+' or '+stripped[5:]); line=indent+stripped; changed+=1
    out.append(line)
if not changed: print('    [note] Known Cookbook marker bug signature not present; upstream may already contain the fix'); raise SystemExit(0)
updated=text[:start]+''.join(out)+text[end:]; compile(updated,str(path),'exec')
backup_dir.mkdir(parents=True,exist_ok=True); backup=backup_dir/(path.name+'.'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.bak'); backup.write_text(text,encoding='utf-8')
fd,tmp=tempfile.mkstemp(prefix='.zar-cookbook-',dir=str(path.parent)); os.close(fd); Path(tmp).write_text(updated,encoding='utf-8'); os.replace(tmp,path); print(f'    [installed] Cookbook completed-download status guard; backup: {backup}')
'@
        Invoke-OdysseusPython $code @($route,$backup)
    }
    $env:PATH = "$bridge;" + (Split-Path -Parent $python) + ';' + $env:PATH
    try { Invoke-CookbookOneClickV10_1 -Mode 'install' } catch { Warn $_.Exception.Message }
    try { Invoke-CookbookProgressV10_2 -Mode 'install' } catch { Warn $_.Exception.Message }
    try { Invoke-CookbookAutoAddV11_6 -Mode 'install' } catch { Warn $_.Exception.Message }
    Okay 'Cookbook now inherits Zarzysseus HF retry/cache behavior; this repair does not update Windows.'
}

function Chroma-Ready {
    try {
        $reply = Invoke-RestMethod -Uri 'http://127.0.0.1:8100/api/v2/heartbeat' -TimeoutSec 3 -ErrorAction Stop
        return ($null -ne $reply)
    } catch { return $false }
}
function Docker-Ready {
    if (-not (Have 'docker')) { return $false }
    try {
        & docker info --format '{{.ServerVersion}}' *> $null
        if ($LASTEXITCODE -ne 0) { return $false }
        & docker compose version *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
function Docker-Compose-Available {
    if (-not (Have 'docker')) { return $false }
    try {
        & docker compose version *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
function Ensure-Docker([switch]$Force) {
    if (-not $Force -and (-not $DockerAutoInstall -or -not $ChromaAutoStart)) {
        Write-Host '    [note] Automatic Docker setup disabled; using an existing ChromaDB if available.'
        return $true
    }
    if (Chroma-Ready) { Okay 'ChromaDB already available; Docker provisioning unnecessary.'; return $true }
    if (Docker-Ready) { Okay 'Docker Engine and Compose v2 ready.'; return $true }
    # Recover PATH first: Docker Desktop might already be installed.
    Refresh-UserPath
    $desktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $desktop) -and
        (-not (Have 'docker') -or -not (Docker-Compose-Available))) {
        try { Ensure-Winget } catch { Warn $_.Exception.Message; return $false }
        Say 'Installing Docker Desktop with Compose through WinGet (admin consent may be requested)'
        Write-Host '    Docker Desktop may require WSL 2, virtualization, a reboot, or first-run terms acceptance.'
        try {
            Invoke-Checked 'winget' @('install','--id','Docker.DockerDesktop','-e','--accept-package-agreements','--accept-source-agreements')
        } catch {
            Warn "Docker Desktop install did not complete: $($_.Exception.Message)"
            return $false
        }
        Refresh-UserPath
    }
    if (-not (Have 'docker')) {
        Warn 'Docker command is not on PATH yet. Open a new PowerShell terminal and rerun docker-setup.'
        return $false
    }
    if (Docker-Ready) { Okay 'Docker Engine and Compose v2 ready.'; return $true }
    if (Test-Path -LiteralPath $desktop) {
        Say 'Starting Docker Desktop (if it is not already running)...'
        try {
            if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath $desktop | Out-Null
            }
        } catch { Warn "Docker Desktop launch: $($_.Exception.Message)" }
    }
    for ($i = 0; $i -lt 45; $i++) {
        if (Docker-Ready) { Okay 'Docker Engine and Compose v2 ready.'; return $true }
        Start-Sleep -Seconds 2
    }
    Warn 'Docker Desktop is installed but the engine/Compose is not yet ready. Complete first-run setup, WSL 2/virtualization or reboot if requested; then rerun docker-setup.'
    return $false
}
function Ensure-Chromadb([switch]$Force) {
    if (-not $ChromaAutoStart -and -not $Force) { Warn 'ChromaDB auto-start disabled by CHROMADB_AUTO_START=0'; return }
    if (Chroma-Ready) { Okay 'ChromaDB heartbeat ready at 127.0.0.1:8100'; return }
    if (-not (Have 'docker')) { Warn 'Docker unavailable. A committed Install/Update or model selection provisions Docker Desktop; alternatively run docker-setup.'; return }
    $composeFiles = @('compose.yaml','compose.yml','docker-compose.yaml','docker-compose.yml')
    if (@($composeFiles | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectDir $_) }).Count -eq 0) {
        Warn 'No Docker Compose file in this checkout; leaving ChromaDB unchanged.'; return
    }
    Push-Location $ProjectDir
    try {
        $null = & docker compose version 2>$null
        if ($LASTEXITCODE -ne 0) { Warn 'Docker Compose unavailable.'; return }
        $services = @(& docker compose config --services 2>$null)
        if ($LASTEXITCODE -ne 0 -or $services -notcontains 'chromadb') {
            Warn 'No chromadb service found in the upstream Compose file.'; return
        }
        Say 'Starting upstream ChromaDB Compose service'
        & docker compose up -d chromadb
        if ($LASTEXITCODE -ne 0) { Warn 'ChromaDB Compose startup failed.'; return }
    } catch { Warn "Cannot start ChromaDB: $($_.Exception.Message)"; return }
    finally { Pop-Location }
    for ($i = 0; $i -lt 15; $i++) {
        if (Chroma-Ready) { Okay 'ChromaDB connected; vector tool index can initialize.'; return }
        Start-Sleep -Seconds 1
    }
    Warn 'ChromaDB started, but its heartbeat did not become ready.'
}
function Ollama-Ready {
    try { $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -ErrorAction Stop; return $true }
    catch { return $false }
}
function Sync-Ollama([string]$PreferredModel = 'llama3.1:8b') {
    if (-not (Ollama-Ready)) { Warn 'Ollama API unreachable; nothing synchronized.'; return }
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Warn 'Odysseus venv missing; install the stack before syncing.'; return }
    $enabled = if ($OllamaToolsEnabled) { '1' } else { '0' }
    $code = @'
import json, sys, uuid
from datetime import datetime, timezone
from pathlib import Path

project_dir, endpoint_url, supports_tools, preferred_model = sys.argv[1:]

import urllib.request
raw = urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5).read()
data = json.loads(raw)
models = [str(m.get("name", "")).strip() for m in data.get("models", []) if m.get("name")]

from core.database import SessionLocal, ModelEndpoint
from src.settings import load_settings, save_settings

db = SessionLocal()
try:
    endpoint = (
        db.query(ModelEndpoint)
        .filter(ModelEndpoint.id == "ollama-local")
        .first()
    )
    now = datetime.now(timezone.utc)
    if endpoint is None:
        endpoint = ModelEndpoint(
            id="ollama-local",
            name="Ollama (Local)",
            base_url=endpoint_url,
            api_key="",
            is_enabled=True,
            hidden_models="[]",
            cached_models=json.dumps(models),
            pinned_models="[]",
            model_type="llm",
            endpoint_kind="local",
            model_refresh_mode="manual",
            supports_tools=(supports_tools.lower() in ("1", "true", "yes", "on")),
            created_at=now,
            updated_at=now,
        )
        db.add(endpoint)
    else:
        endpoint.name = "Ollama (Local)"
        endpoint.base_url = endpoint_url
        endpoint.is_enabled = True
        # Reconcile the live Ollama inventory. A model that is really present
        # in Ollama must not remain hidden/stale in Zarzysseus.
        endpoint.hidden_models = "[]"
        endpoint.cached_models = json.dumps(models)
        endpoint.model_type = "llm"
        endpoint.endpoint_kind = "local"
        endpoint.model_refresh_mode = "manual"
        endpoint.supports_tools = supports_tools.lower() in ("1", "true", "yes", "on")
        endpoint.updated_at = now
    # Odysseus matches exact endpoint base URLs. The UI can create a separate
    # localhost:11434/v1 endpoint while the installer maintains 127.0.0.1.
    # Repair only verified local Ollama /v1 aliases (never vLLM / other ports).
    from urllib.parse import urlsplit
    desired_tools = supports_tools.lower() in ("1", "true", "yes", "on")
    alias_ids = []
    for alias in db.query(ModelEndpoint).all():
        url = urlsplit(alias.base_url or "")
        if (url.scheme in ("http", "https")
                and url.hostname in ("localhost", "127.0.0.1")
                and url.port == 11434
                and url.path.rstrip("/") == "/v1"):
            alias_ids.append(alias.id)
            if alias.supports_tools is not desired_tools:
                alias.supports_tools = desired_tools
                alias.updated_at = now
    db.commit()

    settings = load_settings()
    current_default = str(settings.get("default_model") or "").strip()
    if current_default in models:
        chosen = current_default
    elif preferred_model in models:
        chosen = preferred_model
    else:
        chosen = models[0] if models else ""
    selected_ep = str(settings.get("default_endpoint_id") or "").strip()
    # Keep a deliberate cloud/vLLM default. Only fill an unset/Ollama default.
    ollama_ids = set(alias_ids) | {"ollama-local"}
    if not selected_ep or selected_ep in ollama_ids:
        settings["default_endpoint_id"] = endpoint.id
        if chosen:
            settings["default_model"] = chosen
        save_settings(settings)

    # Keep a content hash so the background sync timer can restart Zarzysseus
    # only when Ollama's model inventory actually changed.
    state_path = Path(project_dir) / "data" / "local" / "ollama-models.sha256"
    state_path.parent.mkdir(parents=True, exist_ok=True)
    import hashlib
    digest = hashlib.sha256(json.dumps({
        "models": sorted(models), "endpoint_url": endpoint_url,
        "native_tools": desired_tools, "ollama_aliases": sorted(alias_ids),
    }, sort_keys=True).encode("utf-8")).hexdigest()
    previous = state_path.read_text(encoding="utf-8").strip() if state_path.exists() else ""
    state_path.write_text(digest + "\n", encoding="utf-8")
    changed = digest != previous

    print(f"Ollama endpoint synced: {endpoint_url}")
    print(f"Ollama models discovered: {len(models)}")
    if chosen:
        print(f"Zarzysseus default LLM: {chosen}")
    else:
        print("Zarzysseus default LLM: not set (Ollama has no models yet)")
    print(f"Ollama native tool calling: {'enabled' if endpoint.supports_tools else 'disabled'}")
    print(f"Ollama native-tool aliases reconciled: {len(alias_ids)}")
    print(f"Ollama model inventory changed: {'yes' if changed else 'no'}")
finally:
    db.close()
'@
    Invoke-OdysseusPython $code @($ProjectDir, 'http://127.0.0.1:11434/v1', $enabled, $PreferredModel)
}
# Agent reliability: same guarded web-routing repair and tests as Linux.
# No authority is granted; tool approvals remain enforced by Odysseus.
function Invoke-AgentReliability([string]$Mode = 'status') {
    $sourceFile = Join-Path $ProjectDir 'src\agent_loop.py'
    $backupDir = Join-Path $ProjectDir 'data\local\patch-backups'
    $code = @'
#!/usr/bin/env python3
"""Zarzysseus guarded runtime adaptation for upstream Odysseus agent routing.
Embedded in both installer scripts; this stand-alone file is retained for tests.
Does not change tool authorization or automatically install external dependencies.
"""
from __future__ import annotations
import ast
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

MARKER = '# ZARZYSSEUS_AGENT_RELIABILITY_V1'
MARKER_FILTER = '# ZARZYSSEUS_AGENT_WEB_ROUTING_V1'
START_ANCHOR = '    def _filter_route_tool_schemas(schemas):\n'
END_ANCHOR = '    def _tool_schemas_for_route(route_state):\n'
HELPER_ANCHOR = '_BROWSER_MCP_PREFIX = "mcp__builtin_browser__"\n'
RULE = '''- ZARZYSSEUS_AGENT_RELIABILITY_V1: For web searches, Reddit, and URL lookups use an actually listed `web_search`, `web_fetch`, or `mcp__builtin_browser__*` tool; NEVER invent a `browser-use` shell executable or Python `page_info()` API. Do not run web-navigation commands through `bash`/PowerShell. If none of these tools is available, explain which capability is missing.\n- In Agent mode, issue the actual tool/function call; do not merely print shell code, describe a plan, or ask the user to execute ordinary permitted read-only actions. Tool calls execute automatically when allowed. If Odysseus requests approval, stop for approval instead of bypassing it. After any tool error, either use an available alternative tool or accurately report the blocker.\n'''
HELPER = '''\n# ZARZYSSEUS_AGENT_RELIABILITY_V1\ndef _zarzysseus_route_web_tools(schemas, request):
    """Narrow *already offered* schemas for clearly requested web actions.

    Does not grant a tool, create privileges, or bypass Odysseus approval.
    Never invents a missing tool. For tasks with no web capability, the
    unchanged schemas remain available for the model to report the blocker.
    """
    import re as _zar_re
    if not isinstance(request, str) or not schemas:
        return schemas
    question = request.lower()
    web_subject = bool(_zar_re.search(
        r"\\b(?:reddit|subreddit|website|webpage|web\\s+page|online|internet|web|https?://|www\\.)\\b|https?://|www\\.", question
    ))
    action = bool(_zar_re.search(
        r"\\b(?:search|look\\s*up|find|browse|open|visit|navigate|check|show|summari[sz]e|latest|recent|top posts?)\\b", question
    ))
    if not (web_subject and action):
        return schemas
    # Use only schemas that the current route and user's permissions already expose.
    def name(schema):
        if not isinstance(schema, dict):
            return ''
        return str(schema.get('function', {}).get('name') or schema.get('name') or '')
    candidates = [s for s in schemas if name(s) in ('web_search', 'web_fetch')]
    # Browser MCP tools are legitimate alternatives when the route provides them.
    browser = [s for s in schemas if name(s).startswith('mcp__builtin_browser__')
               and not name(s).endswith('browser_run_code_unsafe')]
    if candidates or browser:
        # Keep available browser navigation when explicitly requested. No shell.
        return candidates + browser
    return schemas
'''


def digest(s: str) -> str:
    return hashlib.sha256(s.encode('utf-8')).hexdigest()


def report(file: Path, backups: Path) -> int:
    if not file.is_file():
        print('ERROR: Upstream src/agent_loop.py not found; install Odysseus first')
        return 1
    raw = file.read_text(encoding='utf-8')
    print('Agent reliability routing:', 'installed' if MARKER in raw and MARKER_FILTER in raw else 'not installed')
    print('Native tool execution:', 'handled by Odysseus (not overridden)')
    print('Approval policy:', 'Odysseus unchanged')
    print('Tool source:', str(file))
    if MARKER in raw and MARKER_FILTER in raw:
        return 0
    return 1


def build(original: str) -> str:
    if MARKER in original or MARKER_FILTER in original:
        raise ValueError('Partial/unknown existing agent reliability patch; no changes made')
    if original.count(HELPER_ANCHOR) != 1:
        raise ValueError('Upstream browser MCP anchor has changed; no changes made')
    if original.count(START_ANCHOR) != 1 or original.count(END_ANCHOR) != 1:
        raise ValueError('Upstream route function structure changed; no changes made')
    start = original.index(START_ANCHOR)
    end = original.index(END_ANCHOR, start)
    block = original[start:end]
    return_line = '        return schemas\n'
    if block.count(return_line) != 1:
        raise ValueError('Upstream routing return shape changed; no changes made')
    block = block.replace(return_line,
        '        '+MARKER_FILTER+'\n'
        '        # First tool selection only: later rounds may need file/document tools.\n'
        '        try:\n'
        '            _zar_first_round = (round_num == 1)\n'
        '        except NameError:\n'
        '            _zar_first_round = True\n'
        '        if _zar_first_round:\n'
        '            return _zarzysseus_route_web_tools(schemas, _last_user)\n'
        '        return schemas\n', 1)
    updated = original[:start] + block + original[end:]
    updated = updated.replace(HELPER_ANCHOR, HELPER_ANCHOR + HELPER, 1)
    for name in ('_AGENT_RULES', '_API_AGENT_RULES'):
        anchor = name + ' = """\\\n## Base rules\n'
        pattern = re.compile(r'(?m)^' + re.escape(anchor))
        if len(pattern.findall(updated)) != 1:
            raise ValueError('Upstream '+name+' prompt anchor changed; no changes made')
        updated = pattern.sub(lambda _m: anchor + RULE, updated, count=1)
    ast.parse(updated)
    return updated


def atomic_write(path: Path, data: str) -> None:
    fd, fn = tempfile.mkstemp(prefix='.zar-agent-', suffix='.py', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(fn, path.stat().st_mode & 0o777)
        os.replace(fn, path)
    finally:
        if os.path.exists(fn):
            os.unlink(fn)


def install(file: Path, backups: Path) -> int:
    if not file.is_file():
        print('ERROR: Upstream src/agent_loop.py missing; install first')
        return 1
    original = file.read_text(encoding='utf-8')
    if MARKER in original and MARKER_FILTER in original:
        print('    [ready] Agent reliability V1 already installed')
        return 0
    try:
        updated = build(original)
    except (ValueError, SyntaxError) as err:
        print('    [skipped] '+str(err))
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = backups / ('agent_loop.py.' + stamp + '.agent-reliability.bak')
    shutil.copy2(file, backup)
    try:
        atomic_write(file, updated)
    except Exception:
        # Backup exists; if the replacement fails the original remains untouched.
        raise
    manifest = backups / 'agent-reliability-v1.json'
    info = {'backup': str(backup), 'original_sha256': digest(original),
            'installed_sha256': digest(updated), 'file': str(file)}
    manifest.write_text(json.dumps(info, indent=2)+'\n', encoding='utf-8')
    print('    [installed] Agent reliability V1: web routing + automatic tool-call instructions')
    print('    [backup] '+str(backup))
    return 0


def rollback(file: Path, backups: Path) -> int:
    manifest = backups / 'agent-reliability-v1.json'
    if not manifest.is_file():
        print('ERROR: No agent-reliability restore manifest. No file changed.')
        return 2
    state = json.loads(manifest.read_text(encoding='utf-8'))
    if str(file.resolve()) != str(Path(state['file']).resolve()):
        print('ERROR: The backup belongs to a different checkout; no file changed.')
        return 2
    prev = Path(state['backup'])
    if not prev.is_file() or digest(prev.read_text(encoding='utf-8')) != state['original_sha256']:
        print('ERROR: Original backup is missing or modified; no file changed.')
        return 2
    if not file.is_file() or digest(file.read_text(encoding='utf-8')) != state['installed_sha256']:
        print('ERROR: Upstream was modified after the repair; refusing unsafe rollback.')
        print('        Compare manually with '+str(prev))
        return 2
    atomic_write(file, prev.read_text(encoding='utf-8'))
    manifest.unlink()
    print('    [restored] Original upstream agent loop from '+str(prev))
    return 0


def smoke(file: Path, backups: Path) -> int:
    if report(file, backups):
        return 1
    source = file.read_text(encoding='utf-8')
    node = next((n for n in ast.parse(source).body
                 if isinstance(n, ast.FunctionDef) and n.name == '_zarzysseus_route_web_tools'), None)
    if node is None:
        print('ERROR: helper not present or invalid')
        return 1
    ns = {}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(file), 'exec'), ns)
    f = ns[node.name]
    def schema(name):
        return {'type':'function', 'function':{'name':name}}
    offered = [schema(x) for x in ('bash','python','web_search','web_fetch',
                                  'mcp__builtin_browser__browser_navigate',
                                  'mcp__builtin_browser__browser_run_code_unsafe')]
    checks = [
        ('search reddit for latest posts', ['web_search','web_fetch','mcp__builtin_browser__browser_navigate']),
        ('Open https://www.reddit.com/r/unixporn/', ['web_search','web_fetch','mcp__builtin_browser__browser_navigate']),
        ('write a script about logs', [s['function']['name'] for s in offered]),
        ('search local files', [s['function']['name'] for s in offered]),
    ]
    for prompt, names in checks:
        got = [s['function']['name'] for s in f(offered, prompt)]
        if got != names:
            print('FAIL: '+prompt+': '+repr(got))
            return 1
        print('PASS: '+prompt+' -> '+', '.join(got))
    missing = [schema('bash')]
    if f(missing, 'search reddit') != missing:
        print('FAIL: missing tools must not be invented')
        return 1
    print('PASS: missing tools are never invented')
    print('Note: simulated routing only; live model/MCP execution requires testing on your host.')
    return 0


# Agent reliability V2: small intent-specific native tool surfaces.
# V1 is maintained for compatibility with already-installed checkouts.
MARKER_V2 = '# ZARZYSSEUS_AGENT_RELIABILITY_V2'
V1_ROUTE = ("        # ZARZYSSEUS_AGENT_WEB_ROUTING_V1\n"
            "        # First tool selection only: later rounds may need file/document tools.\n"
            "        try:\n"
            "            _zar_first_round = (round_num == 1)\n"
            "        except NameError:\n"
            "            _zar_first_round = True\n"
            "        if _zar_first_round:\n"
            "            return _zarzysseus_route_web_tools(schemas, _last_user)\n"
            "        return schemas\n")
V2_ROUTE = ("        # ZARZYSSEUS_AGENT_WEB_ROUTING_V1\n"
            "        # ZARZYSSEUS_AGENT_RELIABILITY_V2: keep web-only calls focused each round.\n"
            "        return _zarzysseus_route_web_tools_v2(schemas, _last_user)\n")
HELPER_V2 = r"""

# ZARZYSSEUS_AGENT_RELIABILITY_V2
def _zarzysseus_route_web_tools_v2(schemas, request):
    # Filter existing permissions, NOT grant new ones.
    import re as _zar_re
    if not isinstance(request, str) or not schemas:
        return schemas
    txt = request.lower()
    url = bool(_zar_re.search(r'https?://|www\.', txt))
    web_subject = url or bool(_zar_re.search(
        r'\b(?:web|website|webpage|browser|reddit|subreddit|internet|online|site)\b', txt))
    action = bool(_zar_re.search(
        r'\b(?:search|look\s*up|find|browse|open|visit|navigate|check|show|'
        r'summari[sz]e|latest|recent|top|capture|screenshot|click|scroll|type|'
        r'read|take|fill|submit)\b', txt))
    if not (web_subject and action):
        return schemas
    # Only narrow tasks that can be completed entirely with web tools.
    # In mixed workflows, preserving ordinary file/shell/app tools is essential.
    mixed = bool(_zar_re.search(
        r'\b(?:edit|modify|patch|codebase|repository|script|shell|terminal|'
        r'filesystem|local files?|desktop|window manager|docker|systemd|'
        r'save (?:it|the|a|this) (?:to|as)|write (?:a|the|to)|download (?:and|to))\b', txt))
    if mixed:
        return schemas
    def tool_name(schema):
        if not isinstance(schema, dict):
            return ''
        return str((schema.get('function') or {}).get('name') or schema.get('name') or '')
    offered = {tool_name(s): s for s in schemas if tool_name(s)}
    prefix = 'mcp__builtin_browser__'
    visual = bool(_zar_re.search(r'\b(?:screenshot|capture|picture|visually|image|snapshot)\b', txt))
    interaction = bool(_zar_re.search(r'\b(?:click|type|fill|submit|scroll|log\s*in|sign\s*in|interact)\b', txt))
    browser = url or visual or interaction or bool(_zar_re.search(
        r'\b(?:open|navigate|visit|browser|browse)\b', txt))
    names = []
    if browser:
        # Prefer the upstream single-tool browser wrapper if available.
        # On older checkouts the native Playwright MCP tools are used instead.
        if 'private_browser' in offered:
            names = ['private_browser']
        else:
            names = [prefix + 'browser_navigate', prefix + 'browser_snapshot']
            if visual:
                names.append(prefix + 'browser_take_screenshot')
            if interaction:
                names += [prefix + 'browser_click', prefix + 'browser_fill_form',
                          prefix + 'browser_type', prefix + 'browser_press_key']
            names.append(prefix + 'browser_tabs')
    else:
        names = ['web_search', 'web_fetch']
    # Read-only web lookups have a web_search/fetch fallback if the browser isn't available.
    if not any(name in offered for name in names):
        names = ['web_search', 'web_fetch']
    selected = [offered[name] for name in names if name in offered]
    if not selected:
        return schemas  # No fabricated capabilities, preserve upstream error reporting.
    return selected
"""

def build_v2(source: str) -> str:
    if MARKER_V2 in source:
        raise ValueError('V2 marker already exists')
    if source.count(HELPER) != 1 or source.count(V1_ROUTE) != 1:
        raise ValueError('V1 source differs from known guarded patch; no changes made')
    updated = source.replace(HELPER, HELPER + HELPER_V2 + '\n', 1)
    updated = updated.replace(V1_ROUTE, V2_ROUTE, 1)
    ast.parse(updated)
    return updated

_install_v1 = install
_rollback_v1 = rollback

def install(file: Path, backups: Path) -> int:
    if not file.is_file():
        print('ERROR: src/agent_loop.py missing; install Odysseus first')
        return 1
    content = file.read_text(encoding='utf-8')
    if MARKER_V2 in content and V2_ROUTE in content:
        print('    [ready] Agent reliability V2 already installed')
        return 0
    if MARKER_V2 in content:
        print('ERROR: Unknown/incomplete V2 patch; no changes made')
        return 2
    # Keep the known reversible V1 install as the first step for clean installs.
    if MARKER not in content:
        rc = _install_v1(file, backups)
        if rc:
            return rc
        content = file.read_text(encoding='utf-8')
    try:
        updated = build_v2(content)
    except (ValueError, SyntaxError) as err:
        print('    [skipped] ' + str(err))
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    saved = backups / ('agent_loop.py.' + stamp + '.agent-v2.bak')
    shutil.copy2(file, saved)
    atomic_write(file, updated)
    manifest = {'file': str(file.resolve()), 'backup': str(saved),
                'previous_sha256': digest(content), 'installed_sha256': digest(updated)}
    (backups / 'agent-reliability-v2.json').write_text(json.dumps(manifest,indent=2)+'\n', encoding='utf-8')
    print('    [installed] Agent reliability V2: focused browser tools (existing approvals preserved)')
    print('    [backup] ' + str(saved))
    return 0

def report(file: Path, backups: Path) -> int:
    if not file.is_file():
        print('ERROR: src/agent_loop.py missing')
        return 1
    raw = file.read_text(encoding='utf-8')
    state = ('V2 installed' if MARKER_V2 in raw and V2_ROUTE in raw
             else 'legacy V1 installed' if MARKER in raw and MARKER_FILTER in raw
             else 'not installed')
    print('Agent reliability:', state)
    print('Upstream approvals: unchanged; action execution still handled by Odysseus')
    print('Source:', str(file))
    return 0 if state == 'V2 installed' else 1

def smoke(file: Path, backups: Path) -> int:
    if report(file, backups):
        return 1
    node = next((n for n in ast.parse(file.read_text(encoding='utf-8')).body
                 if isinstance(n, ast.FunctionDef) and n.name == '_zarzysseus_route_web_tools_v2'), None)
    if node is None:
        print('FAIL: V2 helper absent')
        return 1
    ns = {}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(file), 'exec'), ns)
    route = ns[node.name]
    def schema(name): return {'type':'function', 'function':{'name':name}}
    prefix = 'mcp__builtin_browser__'
    offered = [schema(x) for x in ('bash', 'python', 'read_file', 'web_search', 'web_fetch',
        prefix+'browser_navigate', prefix+'browser_snapshot', prefix+'browser_take_screenshot',
        prefix+'browser_tabs', prefix+'browser_click', prefix+'browser_fill_form',
        prefix+'browser_type', prefix+'browser_press_key', prefix+'browser_run_code_unsafe')]
    tests = [
        ('Open https://example.com and take a screenshot', [prefix+'browser_navigate', prefix+'browser_snapshot',prefix+'browser_take_screenshot',prefix+'browser_tabs']),
        ('Search Reddit for top posts', ['web_search', 'web_fetch']),
        ('Visit https://example.com and click a link', [prefix+'browser_navigate', prefix+'browser_snapshot',prefix+'browser_click',prefix+'browser_fill_form',prefix+'browser_type',prefix+'browser_press_key',prefix+'browser_tabs']),
        ('Edit my script after reading https://example.com', [s['function']['name'] for s in offered]),
        ('Capture my desktop screen', [s['function']['name'] for s in offered]),
    ]
    for prompt, expected in tests:
        got = [x['function']['name'] for x in route(offered, prompt)]
        if got != expected:
            print('FAIL: '+prompt+'\n  expected='+repr(expected)+'\n  actual='+repr(got))
            return 1
        print('PASS: '+prompt+' -> '+', '.join(got))
    missing = [schema('bash')]
    if route(missing, 'Open https://example.com and take screenshot') != missing:
        print('FAIL: invented missing tools')
        return 1
    print('PASS: missing browser tools never invented')
    print('This is a simulated test; live model-to-MCP tool execution remains unverified.')
    return 0

def rollback(file: Path, backups: Path) -> int:
    manifest = backups / 'agent-reliability-v2.json'
    if manifest.is_file():
        state = json.loads(manifest.read_text(encoding='utf-8'))
        if str(file.resolve()) != str(Path(state['file']).resolve()):
            print('ERROR: V2 backup belongs to a different checkout')
            return 2
        prev = Path(state['backup'])
        if (not prev.is_file() or digest(prev.read_text(encoding='utf-8')) != state['previous_sha256']
           or not file.is_file() or digest(file.read_text(encoding='utf-8')) != state['installed_sha256']):
            print('ERROR: V2 files changed since install; refusing unsafe rollback')
            return 2
        atomic_write(file, prev.read_text(encoding='utf-8'))
        manifest.unlink()
        print('    [restored] Previous V1 source')
    # Once V2 is restored, complete the user's rollback to the ORIGINAL upstream source.
    return _rollback_v1(file, backups)

if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('install','status','smoke','rollback'):
        raise SystemExit('Usage: agent_reliability_v2.py install|status|smoke|rollback <agent_loop.py> <backup_dir>')
    action, src, backup = sys.argv[1:]
    raise SystemExit({'install':install, 'status':report, 'smoke':smoke, 'rollback':rollback}[action](Path(src),Path(backup)))
'@
    Invoke-OdysseusPython $code @($Mode, $sourceFile, $backupDir)
}
function Invoke-AgentRuntimeV3([string]$Mode = 'status') {
    $sourceFile = Join-Path $ProjectDir 'src\agent_loop.py'
    $backupDir = Join-Path $ProjectDir 'data\local\patch-backups'
    $code = @'
#!/usr/bin/env python3
"""Guarded Qwen3-VL thinking-only agent recovery for Zarzysseus.

Only re-prompts the MODEL after a first-round reasoning-only response, for an
explicit browser request already offered a browser navigation tool. Never
runs tools, bypasses permissions, or modifies Odysseus approval behavior.
"""
from __future__ import annotations
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

MARKER = "# ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3"
ANCHOR = """        if _ody_doc_stream_create_mode and tool_blocks:
"""
AFTER = """        tool_blocks, used_native, converted_calls = _resolve_tool_blocks(
"""
LOOP_ANCHOR = "    for round_num in range(1, max_rounds + 1):\n"
RECOVERY = r"""        # ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3
        # Native tools are available, but a local vision model may finish with
        # reasoning-only output and no function-call event. This was otherwise
        # silently treated as a successful turn. A single bounded MODEL retry
        # is allowed here; all executions still flow through upstream dispatch
        # and its original approvals/authorization.
        _zar_browser_names_v3 = {
            str(x.get("function", {}).get("name") or "")
            for x in (all_tool_schemas or []) if isinstance(x, dict)
        }
        _zar_browser_request_v3 = bool(re.search(
            r"\b(?:open|visit|navigate|browse|screenshot)\b",
            str(_last_user or ""), re.I,
        )) and bool(re.search(
            r"https?://|\b(?:website|webpage|browser|screenshot)\b",
            str(_last_user or ""), re.I,
        ))
        _zar_reasoning_only_v3 = (
            not guide_only and not _force_answer
            and not _ody_doc_finetune_mode and not _approved_result_injected
            and round_num in (1, 2)
            and "qwen3-vl" in str(model or "").lower()
            and _is_ollama_openai_compat_url(endpoint_url)
            and _zar_browser_request_v3
            and "mcp__builtin_browser__browser_navigate" in _zar_browser_names_v3
            and not native_tool_calls and not tool_blocks
            and not round_response.strip() and bool(round_reasoning.strip())
        )
        if _zar_reasoning_only_v3 and round_num == 1 and round_num < max_rounds:
            logger.warning(
                "[zarzysseus-agent-v3] reasoning-only first round: "
                "reasoning_chars=%s max_tokens=%s permitted_browser_tools=%s; retrying model once",
                len(round_reasoning), max_tokens,
                len([n for n in _zar_browser_names_v3 if n.startswith("mcp__builtin_browser__")]),
            )
            # This is a fresh model request, not a fabricated function call.
            # Keep the original user request and tool schemas; permissions apply
            # normally to anything the model proposes on the next round.
            _zar_browser_retry_pending_v3 = True
            messages.append({
                "role": "system",
                "content": (
                    "Your previous turn contained reasoning only and did not "
                    "emit a function call or answer. The user requested a "
                    "browser action. Now respond by making a real native "
                    "mcp__builtin_browser__browser_navigate function call "
                    "for the user-provided URL. Do not describe the call or "
                    "claim an action succeeded without a tool result. "
                    "If you cannot call a permitted tool, say so plainly."
                ),
            })
            yield "data: " + json.dumps({
                "type": "agent_step", "round": round_num + 1,
                "note": "Retrying browser tool selection after reasoning-only response",
            }) + "\n\n"
            continue
        if _zar_reasoning_only_v3 and round_num == 2 and _zar_browser_retry_pending_v3:
            logger.warning(
                "[zarzysseus-agent-v3] model retried but still emitted reasoning only; "
                "no browser action was executed"
            )
            _zar_failure_v3 = (
                "I couldn't execute the requested browser action: the model "
                "returned reasoning without an actual tool call on two attempts. "
                "No page was opened or screenshot captured."
            )
            round_response += _zar_failure_v3
            full_response += _zar_failure_v3
            yield "data: " + json.dumps({"delta": _zar_failure_v3}) + "\n\n"
"""
# Note: the precise upstream method call is the only supported insertion target.

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def _verified_source(file: Path) -> str:
    if not file.is_file():
        raise ValueError('src/agent_loop.py not found')
    source = file.read_text('utf-8')
    if '# ZARZYSSEUS_AGENT_RELIABILITY_V2' not in source:
        raise ValueError('Agent Reliability V2 required; run agent-repair from V2 first')
    return source

def build(source: str) -> str:
    if MARKER in source:
        raise ValueError('V3 already present; refusing duplicate injection')
    if source.count(ANCHOR) != 1 or source.count(AFTER) != 1 or source.count(LOOP_ANCHOR) != 1:
        raise ValueError('Expected upstream tool-dispatch structure changed; no source change')
    if not (source.index(AFTER) < source.index(ANCHOR)):
        raise ValueError('Tool-dispatch anchors out of order')
    if 'native_tool_calls = data.get("calls", [])' not in source:
        raise ValueError('Upstream native-tool event handling changed')
    # Insert exactly after the conversion call and before the document special-case.
    modified = source.replace(ANCHOR, RECOVERY + ANCHOR, 1)
    modified = modified.replace(LOOP_ANCHOR, "    _zar_browser_retry_pending_v3 = False\n" + LOOP_ANCHOR, 1)
    ast.parse(modified)
    return modified

def atomic_write(path: Path, contents: bytes):
    fd, name = tempfile.mkstemp(prefix='.zar-runtime-v3-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(contents); out.flush(); os.fsync(out.fileno())
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)

def manifest_path(backups: Path) -> Path:
    return backups/'agent-thinking-recovery-v3.json'

def status(file: Path, backups: Path) -> int:
    source = _verified_source(file)
    found = MARKER in source
    manifest = manifest_path(backups)
    print('Agent thinking-only recovery V3:', 'installed' if found else 'not installed')
    print('Backup manifest:', 'present' if manifest.is_file() else 'absent')
    print('Automatic tools:', 'Odysseus native dispatch only (approvals unchanged)')
    if found != manifest.is_file():
        print('WARNING: source and backup manifest disagree; repair/rollback disabled until reconciled')
        return 2
    return 0 if found else 1

def install(file: Path, backups: Path) -> int:
    source = _verified_source(file)
    manifest = manifest_path(backups)
    if MARKER in source:
        if not manifest.is_file():
            print('ERROR: V3 marker present but backup manifest absent; refusing unmanaged install')
            return 2
        state = json.loads(manifest.read_text('utf-8'))
        if digest(source.encode('utf-8')) != state['installed_sha256']:
            print('ERROR: V3 source changed since install; refusing automatic re-install')
            return 2
        print('    [ready] Agent thinking-only recovery V3 already installed')
        return 0
    if manifest.is_file():
        print('ERROR: V3 manifest exists but patch is missing; refusing overwrite')
        return 2
    try:
        patched = build(source)
    except (ValueError, SyntaxError) as err:
        print('ERROR:', err)
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups/'agent-thinking-recovery-v3.before.py'
    if backup.exists():
        print('ERROR: prior backup exists; refusing overwrite')
        return 2
    original_bytes = source.encode('utf-8')
    patched_bytes = patched.encode('utf-8')
    # Write a private source backup and an immutable-digest rollback manifest.
    backup.write_bytes(original_bytes)
    os.chmod(backup, 0o600)
    state = {'file': str(file.resolve()), 'backup': str(backup.resolve()),
             'previous_sha256': digest(original_bytes),
             'installed_sha256': digest(patched_bytes), 'version': 3}
    try:
        atomic_write(file, patched_bytes)
        manifest.write_text(json.dumps(state, indent=2)+'\n', encoding='utf-8')
        os.chmod(manifest, 0o600)
    except Exception:
        if file.is_file() and digest(file.read_bytes()) == digest(patched_bytes):
            atomic_write(file, original_bytes)
        raise
    print('    [installed] Agent thinking-only browser recovery V3 (one bounded retry)')
    print('    [backup]', backup)
    return 0

def rollback(file: Path, backups: Path) -> int:
    manifest = manifest_path(backups)
    if not manifest.is_file():
        if MARKER in _verified_source(file):
            print('ERROR: Cannot roll back V3 without manifest')
            return 2
        print('    [note] No V3 patch installed')
        return 0
    state = json.loads(manifest.read_text('utf-8'))
    backup = Path(state['backup'])
    if str(file.resolve()) != state['file'] or not backup.is_file():
        print('ERROR: V3 backup does not match checkout')
        return 2
    if digest(file.read_bytes()) != state['installed_sha256']:
        print('ERROR: Source changed since V3 installation, refusing rollback')
        return 2
    saved = backup.read_bytes()
    if digest(saved) != state['previous_sha256']:
        print('ERROR: Backup digest mismatch, refusing rollback')
        return 2
    atomic_write(file, saved)
    manifest.unlink()
    backup.unlink()
    print('    [restored] Exact Agent Reliability V2 source')
    return 0

def smoke(file: Path, backups: Path) -> int:
    source = _verified_source(file)
    mock = build(source) if MARKER not in source else source
    ast.parse(mock)
    required = ('round_num in (1, 2)', 'round_num == 1 and round_num < max_rounds',
                'and not native_tool_calls and not tool_blocks',
                'and _zar_browser_retry_pending_v3',
                'mcp__builtin_browser__browser_navigate', 'No page was opened or screenshot captured.')
    for part in required:
        if part not in mock:
            print('FAIL: missing safeguard:', part); return 1
    print('PASS: V3 source compiles, retries once on qualifying reasoning-only Qwen browser requests')
    print('PASS: existing allowed tool schemas and upstream execution policy remain in control')
    print('NOTE: simulated/source checks only; live browser calls are not proven')
    return 0

if __name__=='__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('install','status','rollback','smoke'):
        raise SystemExit('Usage: agent_runtime_v3.py install|status|rollback|smoke <agent_loop.py> <backup_dir>')
    command, source_file, backups_dir = sys.argv[1:]
    try:
        raise SystemExit({'install':install,'status':status,'rollback':rollback,'smoke':smoke}[command](Path(source_file),Path(backups_dir)))
    except Exception as e:
        print('ERROR:', str(e))
        raise SystemExit(2)
'@
    Invoke-OdysseusPython $code @($Mode, $sourceFile, $backupDir)
}
function Invoke-AgentRuntimeV4([string]$Mode = 'status') {
    $code = @'
#!/usr/bin/env python3
"""Experimental guarded Zarzysseus compact browser tool-call fallback V4.

Targets an *installed* Odysseus agent_loop.py already patched with Zarzysseus
reliability V2 and thinking-only recovery V3. It does NOT execute browser tools.
The normal Odysseus executor and approvals remain the sole authority.

Usage:
 python3 zarzysseus_browser_fallback_v4.py install ~/odysseus
 python3 zarzysseus_browser_fallback_v4.py status ~/odysseus
 python3 zarzysseus_browser_fallback_v4.py rollback ~/odysseus
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

MARKER = "# ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4"
HELPER_ANCHOR = 'logger = logging.getLogger(__name__)\n'
INJECT_ANCHOR = '        # ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3\n'
LOOP_ANCHOR = '    for round_num in range(1, max_rounds + 1):\n'

HELPER = r'''
# ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4
async def _zar_compact_browser_tool_proposal_v4(
    *, endpoint_url, model, headers, schema, target_url, timeout
):
    """Request ONE real native tool proposal; never execute anything here.

    The source URL must be in the user's explicit request, and the returned
    proposal must match it exactly for navigation. All authorization and tool
    execution are handled later by the regular Odysseus tool pipeline.
    """
    tool_name = str((schema.get("function") or {}).get("name") or "")
    if tool_name not in {
        "mcp__builtin_browser__browser_navigate",
        "mcp__builtin_browser__browser_take_screenshot",
    }:
        return []
    if not isinstance(target_url, str) or not target_url.startswith(("https://", "http://")):
        return []
    prompt = (
        "You are a one-action tool-selection assistant. The user explicitly "
        "requested this website. You have one allowed tool. Make exactly one "
        "real native function call now; do not write explanations or pseudo-calls. "
        "Never choose a URL different from the user's URL."
    )
    if tool_name.endswith("browser_navigate"):
        instruction = "Navigate to " + target_url + " using your single available function."
    else:
        instruction = (
            "The browser was already navigated to " + target_url + ". "
            "Take a screenshot of the current browser page using the single available function."
        )
    try:
        from urllib.parse import urlsplit as _zar_urlsplit
        expected = _zar_urlsplit(target_url)
        if not expected.hostname or expected.username or expected.password:
            return []
        proposals = []
        async for event in stream_llm(
            endpoint_url, model,
            [{"role": "system", "content": prompt},
             {"role": "user", "content": instruction}],
            temperature=0, max_tokens=1024, headers=headers,
            timeout=min(max(int(timeout), 10), 90), tools=[schema],
            workload="foreground",
        ):
            if event.startswith("event: error"):
                return []
            if not event.startswith("data: "):
                continue
            try:
                data = json.loads(event.split("data: ", 1)[1].strip())
            except (ValueError, IndexError):
                continue
            if data.get("type") != "tool_calls":
                continue
            for call in data.get("calls") or []:
                if call.get("name") != tool_name:
                    continue
                raw_args = call.get("arguments", "{}")
                try:
                    args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
                except (TypeError, ValueError):
                    continue
                if not isinstance(args, dict):
                    continue
                if tool_name.endswith("browser_navigate"):
                    actual_url = args.get("url")
                    if not isinstance(actual_url, str):
                        continue
                    actual_parts = _zar_urlsplit(actual_url)
                    exact_match = actual_url == target_url
                    root_slash_alias = (
                        expected.scheme == actual_parts.scheme
                        and expected.netloc == actual_parts.netloc
                        and expected.path in ("", "/")
                        and actual_parts.path in ("", "/")
                        and expected.query == actual_parts.query
                        and expected.fragment == actual_parts.fragment
                    )
                    if not (exact_match or root_slash_alias):
                        continue
                    # Restore the literal authorized URL in the proposal.
                    args["url"] = target_url
                else:
                    # No file upload or arbitrary browser scripting here.
                    if any(k not in {"type", "filename", "fullPage"} for k in args):
                        continue
                proposals.append({
                    "id": str(call.get("id") or "zar_browser_v4"),
                    "name": tool_name,
                    "arguments": json.dumps(args),
                })
        return proposals[:1]
    except Exception as error:
        logger.warning("[zarzysseus-agent-v4] compact proposal unavailable: %s", type(error).__name__)
        return []

'''

INJECT = r'''        # ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4
        # Only activates for a Qwen3-VL reasoning-only response to an explicit
        # navigate/screenshot request. It offers one already-authorized schema
        # to a *separate* compact model invocation; it never executes any tool.
        # Successfully proposed calls reenter the normal Odysseus dispatcher.
        if (
            not guide_only and not _force_answer and not plan_mode
            and not _ody_doc_finetune_mode and not _approved_result_injected
            and "qwen3-vl" in str(model or "").lower()
            and _is_ollama_openai_compat_url(endpoint_url)
            and not native_tool_calls and not tool_blocks
            and not round_response.strip() and bool(round_reasoning.strip())
            and round_num <= 4
        ):
            _zar_text_v4 = str(_last_user or "")
            _zar_browser_intent_v4 = bool(re.search(
                r"\b(?:open|visit|navigate|browse|screenshot|capture)\b",
                _zar_text_v4, re.I,
            ))
            _zar_url_match_v4 = re.search(
                r"https?://[^\s<>\"'\)\]]+", _zar_text_v4, re.I,
            )
            if _zar_browser_intent_v4 and _zar_url_match_v4:
                _zar_target_url_v4 = _zar_url_match_v4.group(0).rstrip(".,;:!?")
                _zar_by_name_v4 = {
                    str((s.get("function") or {}).get("name") or ""): s
                    for s in (all_tool_schemas or []) if isinstance(s, dict)
                }
                _zar_nav_v4 = "mcp__builtin_browser__browser_navigate"
                _zar_shot_v4 = "mcp__builtin_browser__browser_take_screenshot"
                _zar_did_nav_v4 = any(
                    e.get("tool") == _zar_nav_v4
                    for e in tool_events if isinstance(e, dict)
                )
                _zar_nav_success_v4 = any(
                    e.get("tool") == _zar_nav_v4
                    and e.get("exit_code") in (None, 0)
                    and not re.search(r"(?:^|\n)\s*(?:error|failed):", str(e.get("output") or ""), re.I)
                    for e in tool_events if isinstance(e, dict)
                )
                _zar_did_shot_v4 = any(
                    e.get("tool") == _zar_shot_v4
                    for e in tool_events if isinstance(e, dict)
                )
                _zar_want_shot_v4 = bool(re.search(
                    r"\b(?:screenshot|capture|snapshot|picture)\b",
                    _zar_text_v4, re.I,
                ))
                _zar_next_tool_v4 = None
                if not _zar_did_nav_v4 and _zar_nav_v4 in _zar_by_name_v4:
                    _zar_next_tool_v4 = _zar_nav_v4
                elif (
                    _zar_nav_success_v4 and _zar_want_shot_v4 and not _zar_did_shot_v4
                    and _zar_shot_v4 in _zar_by_name_v4
                ):
                    _zar_next_tool_v4 = _zar_shot_v4
                if _zar_next_tool_v4 and _zar_next_tool_v4 not in _zar_compact_attempted_v4:
                    _zar_compact_attempted_v4.add(_zar_next_tool_v4)
                    logger.info(
                        "[zarzysseus-agent-v4] requesting compact native proposal tool=%s round=%s",
                        _zar_next_tool_v4, round_num,
                    )
                    _zar_proposals_v4 = await _zar_compact_browser_tool_proposal_v4(
                        endpoint_url=endpoint_url, model=model, headers=headers,
                        schema=_zar_by_name_v4[_zar_next_tool_v4],
                        target_url=_zar_target_url_v4,
                        timeout=agent_stream_timeout,
                    )
                    if _zar_proposals_v4:
                        _zar_blocks_v4, _zar_native_v4, _zar_converted_v4 = _resolve_tool_blocks(
                            round_response, _zar_proposals_v4, round_num,
                            is_api_model=True,
                        )
                        if _zar_blocks_v4 and _zar_native_v4:
                            native_tool_calls = _zar_proposals_v4
                            tool_blocks = _zar_blocks_v4
                            used_native = _zar_native_v4
                            converted_calls = _zar_converted_v4
                            logger.info(
                                "[zarzysseus-agent-v4] native proposal accepted; handing to upstream executor tool=%s",
                                _zar_next_tool_v4,
                            )
                        else:
                            logger.warning("[zarzysseus-agent-v4] proposal could not be converted; no execution")
                    else:
                        logger.warning("[zarzysseus-agent-v4] no valid native tool proposal returned")
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def get_paths(checkout: Path):
    root = checkout.expanduser().resolve()
    source = root / 'src' / 'agent_loop.py'
    backup_dir = root / 'data' / 'local' / 'patch-backups'
    return source, backup_dir / 'agent-compact-browser-v4.before.py', backup_dir / 'agent-compact-browser-v4.json'


def read_checked(path: Path) -> str:
    if not path.is_file():
        raise ValueError(f'Odysseus source not found: {path}')
    src = path.read_text(encoding='utf-8')
    if '# ZARZYSSEUS_AGENT_RELIABILITY_V2' not in src or '# ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3' not in src:
        raise ValueError('Expected V2 and V3 markers missing; install V3 first')
    return src


def build(src: str) -> str:
    if MARKER in src:
        raise ValueError('V4 already present')
    for anchor in (HELPER_ANCHOR, INJECT_ANCHOR, LOOP_ANCHOR):
        if src.count(anchor) != 1:
            raise ValueError('Unexpected upstream structure: anchor count for ' + repr(anchor))
    updated = src.replace(HELPER_ANCHOR, HELPER_ANCHOR + HELPER, 1)
    updated = updated.replace(LOOP_ANCHOR, '    _zar_compact_attempted_v4 = set()\n' + LOOP_ANCHOR, 1)
    updated = updated.replace(INJECT_ANCHOR, INJECT + INJECT_ANCHOR, 1)
    ast.parse(updated)
    return updated


def atomic_write(path: Path, content: bytes):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.zar-v4-')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'status', 'rollback'))
    parser.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = parser.parse_args()
    source, backup, manifest = get_paths(Path(args.checkout))
    try:
        src = read_checked(source)
        if args.action == 'status':
            is_installed = MARKER in src
            print('V4 compact browser fallback:', 'installed' if is_installed else 'not installed')
            print('Backup manifest:', 'present' if manifest.exists() else 'absent')
            if manifest.exists():
                state = json.loads(manifest.read_text('utf-8'))
                if is_installed and sha(src.encode('utf-8')) != state.get('installed_sha256'):
                    raise ValueError('Patched source changed since installation')
            return 0 if is_installed else 1
        if args.action == 'install':
            if MARKER in src:
                if not manifest.exists():
                    raise ValueError('V4 is present without a manifest; refusing unmanaged update')
                state = json.loads(manifest.read_text('utf-8'))
                if sha(src.encode('utf-8')) != state.get('installed_sha256'):
                    raise ValueError('V4 source differs from recorded installation; refusing overwrite')
                print('V4 already installed and unchanged')
                return 0
            if manifest.exists() or backup.exists():
                raise ValueError('Existing V4 backup/manifest must be reconciled first')
            updated = build(src)
            backup.parent.mkdir(parents=True, exist_ok=True)
            orig_bytes = src.encode('utf-8')
            new_bytes = updated.encode('utf-8')
            backup.write_bytes(orig_bytes)
            os.chmod(backup, 0o600)
            state = {'source': str(source), 'backup': str(backup),
                     'previous_sha256': sha(orig_bytes), 'installed_sha256': sha(new_bytes)}
            try:
                atomic_write(source, new_bytes)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if sha(source.read_bytes()) == sha(new_bytes):
                    atomic_write(source, orig_bytes)
                raise
            print('Installed compact browser proposal fallback V4 (upstream approvals unchanged).')
            print('Backup:', backup)
            return 0
        if not manifest.exists() or not backup.exists():
            raise ValueError('Backup and manifest required for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if MARKER not in src or sha(src.encode('utf-8')) != state['installed_sha256']:
            raise ValueError('Installed V4 source differs from manifest; refusing rollback')
        original = backup.read_bytes()
        if sha(original) != state['previous_sha256']:
            raise ValueError('Original backup digest mismatch; refusing rollback')
        atomic_write(source, original)
        manifest.unlink()
        backup.unlink()
        print('V4 removed; original V3 source restored exactly.')
        return 0
    except (ValueError, OSError, SyntaxError, json.JSONDecodeError) as exc:
        print('ERROR:', exc, file=sys.stderr)
        return 2

if __name__ == '__main__':
    sys.exit(main())

'@
    Invoke-OdysseusPython $code @($Mode, $ProjectDir)
}
function Invoke-AgentRuntimeV5([string]$Mode = 'status') {
    $code = @'
#!/usr/bin/env python3
"""Zarzysseus V5: preserve authorized browser screenshot continuation after approval.

Requires the installed, unchanged V4 agent source, with its manifest present.
This is a source-guarded compatibility repair, not an alternative executor.
CLI: install|status|rollback CHECKOUT_DIR
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

MARKER = '# ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5'
V4_MARKER = '# ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4'

REQUEST_ANCHOR = '    _last_user = _extract_last_user_message(messages)\n'
TOOLS_ANCHOR = '    _intent_domains = set(_intent.get("domains") or set())\n'
V2_ANCHOR = '        return _zarzysseus_route_web_tools_v2(schemas, _last_user)\n'
QWEN_ANCHOR = '                _zar_text = _last_user or ""\n'
V4_REQ_ANCHOR = '            and not _ody_doc_finetune_mode and not _approved_result_injected\n'
V4_TEXT_ANCHOR = '            _zar_text_v4 = str(_last_user or "")\n'
NAV_SUCCESS_ANCHOR = '                    and e.get("exit_code") in (None, 0)\n'

REQUEST_BLOCK = r'''    # ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5
    # Approval restarts the request with new tool retrieval. Retain the user\'s
    # original screenshot instruction ONLY for a matching sealed browser navigation.
    # No tool is executed here, and this cannot grant an otherwise disabled tool.
    _zar_approved_browser_followup_v5 = ""
    _zar_approved_browser_target_v5 = ""
    if (
        exact_approval is not None and mcp_mgr is not None
        and not guide_only and not plan_mode
        and getattr(exact_approval.pending, "tool_name", None)
            == "mcp__builtin_browser__browser_navigate"
    ):
        try:
            from urllib.parse import urlsplit as _zar_urlsplit_v5
            _zar_pending_v5 = exact_approval.pending
            _zar_exact_valid_v5 = exact_approval.matches(
                owner=owner, session_id=session_id,
                tool_name=_zar_pending_v5.tool_name,
                content=_zar_pending_v5.content, workspace=workspace,
            )
            _zar_approved_url_v5 = ""
            if _zar_exact_valid_v5:
                _zar_pending_args_v5 = json.loads(_zar_pending_v5.content)
                if isinstance(_zar_pending_args_v5, dict):
                    _zar_approved_url_v5 = str(_zar_pending_args_v5.get("url") or "")
            _zar_parsed_v5 = _zar_urlsplit_v5(_zar_approved_url_v5)
            if (_zar_parsed_v5.scheme in ("http", "https") and _zar_parsed_v5.hostname
                    and not _zar_parsed_v5.username and not _zar_parsed_v5.password):
                # Only explicit user-authored messages count: no assistant text,
                # tool output, fetched pages, or approval note can trigger this.
                for _zar_msg_v5 in reversed(messages[-24:]):
                    if not isinstance(_zar_msg_v5, dict) or _zar_msg_v5.get("role") != "user":
                        continue
                    _zar_content_v5 = _zar_msg_v5.get("content")
                    if not isinstance(_zar_content_v5, str):
                        continue
                    _zar_user_urls_v5 = [
                        candidate.rstrip(".,;:!?")
                        for candidate in re.findall(r"https?://[^\s<>\"'\)\]]+", _zar_content_v5, re.I)
                    ]
                    if _zar_approved_url_v5 not in _zar_user_urls_v5:
                        continue
                    # The most recent user turn mentioning this URL controls
                    # intent. An older screenshot request cannot be resurrected.
                    if not re.search(r"\b(?:screenshot|screen\s*shot|capture|picture)\b", _zar_content_v5, re.I):
                        break
                    _zar_approved_browser_followup_v5 = _zar_content_v5
                    _zar_approved_browser_target_v5 = _zar_approved_url_v5
                    _last_user = _zar_content_v5  # preserve tool-routing context after approval
                    logger.info("[zarzysseus-agent-v5] validated approved browser screenshot continuation")
                    break
        except (AttributeError, ValueError, TypeError, json.JSONDecodeError):
            # Unexpected request/approval shapes fail closed.
            pass
'''

TOOLS_BLOCK = r'''    # ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5_TOOL_KEEP
    # Recheck the current enabled MCP inventory and disabled-tool policy.
    # This only reintroduces an *existing* screenshot schema for this request.
    if _zar_approved_browser_followup_v5 and mcp_mgr is not None and not guide_only:
        _zar_screenshot_name_v5 = "mcp__builtin_browser__browser_take_screenshot"
        if _zar_screenshot_name_v5 not in disabled_tools:
            try:
                _zar_enabled_schemas_v5 = mcp_mgr.get_all_openai_schemas(_mcp_disabled_map)
                if any(
                    (s.get("function") or {}).get("name") == _zar_screenshot_name_v5
                    for s in _zar_enabled_schemas_v5 if isinstance(s, dict)
                ):
                    if _relevant_tools is None:
                        _relevant_tools = set()
                    _relevant_tools.add(_zar_screenshot_name_v5)
                    logger.info("[zarzysseus-agent-v5] retained enabled screenshot schema for approved continuation")
                else:
                    logger.warning("[zarzysseus-agent-v5] screenshot tool unavailable or disabled")
            except Exception as _zar_err_v5:
                logger.warning("[zarzysseus-agent-v5] screenshot capability check failed: %s", type(_zar_err_v5).__name__)
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def paths(checkout: Path):
    root = checkout.expanduser().resolve()
    backup_dir = root / 'data' / 'local' / 'patch-backups'
    return (root / 'src' / 'agent_loop.py',
            backup_dir / 'agent-approved-browser-v5.before.py',
            backup_dir / 'agent-approved-browser-v5.json',
            backup_dir / 'agent-compact-browser-v4.json')


def replace_one(src: str, old: str, new: str) -> str:
    if src.count(old) != 1:
        raise ValueError('Upstream source anchor changed or ambiguous: ' + repr(old[:85]))
    return src.replace(old, new, 1)


def build(src: str) -> str:
    if MARKER in src:
        raise ValueError('V5 already installed')
    if V4_MARKER not in src or '# ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3' not in src:
        raise ValueError('Requires V4/V3 installed source')
    src = replace_one(src, REQUEST_ANCHOR, REQUEST_ANCHOR + REQUEST_BLOCK)
    src = replace_one(src, TOOLS_ANCHOR, TOOLS_BLOCK + TOOLS_ANCHOR)
    # Scope changes to the V4 runtime block rather than an unrelated V3 retry.
    v4_start = src.find('        # ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4\n')
    v4_end = src.find('        # ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3\n', v4_start)
    if v4_start < 0 or v4_end < 0:
        raise ValueError('Expected adjacent V4/V3 runtime blocks missing')
    v4_block = src[v4_start:v4_end]
    v4_block = replace_one(v4_block, V4_REQ_ANCHOR, '            and not _ody_doc_finetune_mode\n            and (not _approved_result_injected or bool(_zar_approved_browser_followup_v5))\n')
    v4_block = replace_one(v4_block, NAV_SUCCESS_ANCHOR, '                    and e.get("exit_code") == 0\n')
    src = src[:v4_start] + v4_block + src[v4_end:]
    ast.parse(src)
    return src


def write_atomic(path: Path, data: bytes):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.zar-v5-')
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('install', 'status', 'rollback'))
    parser.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = parser.parse_args()
    source, backup, manifest, v4_manifest = paths(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Missing agent source: {source}')
        src_bytes = source.read_bytes()
        src = src_bytes.decode('utf-8')
        if args.mode == 'status':
            found = MARKER in src
            print('V5 approved browser continuation:', 'installed' if found else 'not installed')
            print('V5 backup manifest:', 'present' if manifest.exists() else 'absent')
            if found:
                if not manifest.exists() or digest(src_bytes) != json.loads(manifest.read_text())['installed_sha256']:
                    raise ValueError('V5 source differs from its manifest')
            return 0 if found else 1
        if args.mode == 'install':
            if MARKER in src:
                if not manifest.exists() or digest(src_bytes) != json.loads(manifest.read_text())['installed_sha256']:
                    raise ValueError('V5 already installed but source/manifest differs; refusing overwrite')
                print('    [ready] Agent approved-browser continuation V5 already installed')
                return 0
            if manifest.exists() or backup.exists():
                raise ValueError('Existing V5 backup/manifest must be reconciled first')
            if not v4_manifest.exists():
                raise ValueError('V4 backup manifest missing; V5 refuses unmanaged source')
            v4_state = json.loads(v4_manifest.read_text())
            if digest(src_bytes) != v4_state.get('installed_sha256'):
                raise ValueError('Installed V4 does not match saved digest; V5 refuses to overwrite')
            result = build(src).encode('utf-8')
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(src_bytes)
            os.chmod(backup, 0o600)
            state = dict(previous_sha256=digest(src_bytes), installed_sha256=digest(result),
                         source=str(source), backup=str(backup))
            try:
                write_atomic(source, result)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(result):
                    write_atomic(source, src_bytes)
                raise
            print('Installed Agent approved-browser screenshot continuation V5; upstream approvals unchanged.')
            print('Backup:', backup)
            return 0
        if not manifest.exists() or not backup.exists():
            raise ValueError('V5 manifest and backup required for rollback')
        state = json.loads(manifest.read_text())
        if MARKER not in src or digest(src_bytes) != state['installed_sha256']:
            raise ValueError('V5 source changed since installation; refusing rollback')
        previous = backup.read_bytes()
        if digest(previous) != state['previous_sha256']:
            raise ValueError('V5 backup corrupted; refusing rollback')
        write_atomic(source, previous)
        manifest.unlink()
        backup.unlink()
        print('V5 rolled back: exact V4 source restored')
        return 0
    except (ValueError, KeyError, OSError, UnicodeError, SyntaxError, json.JSONDecodeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

'@
    Invoke-OdysseusPython $code @($Mode, $ProjectDir)
}
function Invoke-AgentRuntimeV6([string]$Mode = 'status') {
    $code = @'
#!/usr/bin/env python3
"""Zarzysseus V6: tightly scoped screenshot step after verified approved navigation.

Upstream tool policy/approval and the existing executor remain authoritative.
This repair queues an already user-requested screenshot rather than relying on
another native model tool proposal after a reasoning-only continuation.

CLI: python zarzysseus_browser_screenshot_v6.py install|status|rollback CHECKOUT
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

MARKER = '# ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6'
PREV_MARKER = '# ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5'
INSERT_ANCHOR = '        # ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4\n'
BLOCK = r'''        # ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6
        # This is a deterministic continuation of an EXPLICIT, verified user
        # screenshot request, NOT a model-generated tool proposal. Only after
        # an exact approved browser navigation has succeeded, the screenshot
        # function is still in the CURRENT supplied schemas, and its arguments
        # schema has no mandatory fields, queue one capture through Odysseus's
        # regular converter/policy/approval/execution path.
        if (
            not guide_only and not _force_answer and not plan_mode
            and not _ody_doc_finetune_mode and _approved_result_injected
            and bool(_zar_approved_browser_followup_v5)
            and bool(_zar_approved_browser_target_v5)
            and round_num == 1
            and "qwen3-vl" in str(model or "").lower()
            and _is_ollama_openai_compat_url(endpoint_url)
            and not tool_blocks and not native_tool_calls
            and not round_response.strip() and bool(round_reasoning.strip())
        ):
            _zar_nav_v6 = "mcp__builtin_browser__browser_navigate"
            _zar_shot_v6 = "mcp__builtin_browser__browser_take_screenshot"
            _zar_nav_ok_v6 = any(
                isinstance(e, dict)
                and e.get("tool") == _zar_nav_v6
                and e.get("exit_code") == 0
                and not re.search(r"(?:^|\n)\s*(?:error|failed):", str(e.get("output") or ""), re.I)
                for e in tool_events
            )
            _zar_shot_already_v6 = any(
                isinstance(e, dict) and e.get("tool") == _zar_shot_v6
                for e in tool_events
            )
            _zar_schemas_v6 = [
                s for s in (all_tool_schemas or [])
                if isinstance(s, dict)
                and (s.get("function") or {}).get("name") == _zar_shot_v6
            ]
            if _zar_nav_ok_v6 and not _zar_shot_already_v6 and len(_zar_schemas_v6) == 1:
                _zar_params_v6 = (_zar_schemas_v6[0].get("function") or {}).get("parameters") or {}
                _zar_required_v6 = _zar_params_v6.get("required", []) if isinstance(_zar_params_v6, dict) else None
                if _zar_required_v6 == []:
                    # Empty args: the MCP tool uses its normal defaults; no
                    # new URL, arbitrary filename, script, or external path.
                    _zar_explicit_call_v6 = [{
                        "id": "zarzysseus_explicit_screenshot_v6",
                        "name": _zar_shot_v6,
                        "arguments": "{}",
                    }]
                    _zar_blocks_v6, _zar_native_v6, _zar_converted_v6 = _resolve_tool_blocks(
                        round_response, _zar_explicit_call_v6, round_num, is_api_model=True,
                    )
                    if len(_zar_blocks_v6) == 1 and _zar_native_v6 and _zar_blocks_v6[0].tool_type == _zar_shot_v6:
                        native_tool_calls = _zar_explicit_call_v6
                        tool_blocks = _zar_blocks_v6
                        used_native = _zar_native_v6
                        converted_calls = _zar_converted_v6
                        logger.info(
                            "[zarzysseus-agent-v6] queued explicitly requested screenshot via upstream approvals/executor"
                        )
                    else:
                        logger.warning("[zarzysseus-agent-v6] screenshot call converter refused; no action queued")
                else:
                    logger.warning("[zarzysseus-agent-v6] screenshot schema requires arguments; refusing default capture")
            elif _zar_nav_ok_v6 and not _zar_shot_already_v6:
                logger.warning("[zarzysseus-agent-v6] screenshot schema missing or ambiguous; no action queued")
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def locations(root: Path):
    root = root.expanduser().resolve()
    backups = root / 'data' / 'local' / 'patch-backups'
    return (
        root / 'src' / 'agent_loop.py',
        backups / 'agent-explicit-screenshot-v6.before.py',
        backups / 'agent-explicit-screenshot-v6.json',
        backups / 'agent-approved-browser-v5.json',
    )


def patch_source(source: str) -> str:
    if MARKER in source:
        raise ValueError('V6 is already installed')
    if PREV_MARKER not in source:
        raise ValueError('Install V5 before V6')
    if source.count(INSERT_ANCHOR) != 1:
        raise ValueError('Unexpected upstream V4 anchor (missing or ambiguous)')
    patched = source.replace(INSERT_ANCHOR, BLOCK + INSERT_ANCHOR, 1)
    ast.parse(patched)
    return patched


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-v6-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation', choices=['install', 'status', 'rollback'])
    p.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = p.parse_args(argv)
    source, backup, manifest, prev_manifest = locations(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Missing upstream agent: {source}')
        original = source.read_bytes()
        current = original.decode('utf-8')
        installed = MARKER in current
        if args.operation == 'status':
            print('V6 explicit screenshot continuation:', 'installed' if installed else 'not installed')
            print('V6 backup manifest:', 'present' if manifest.is_file() else 'missing')
            if installed:
                if not manifest.exists() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Installed V6 source differs from recorded digest')
            return 0 if installed else 1
        if args.operation == 'install':
            if installed:
                if not manifest.exists() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Existing V6 was edited or manifest missing; refusing replacement')
                print('    [ready] V6 explicit screenshot continuation already installed')
                return 0
            if manifest.exists() or backup.exists():
                raise ValueError('Stale V6 backups exist: reconcile before installing')
            if not prev_manifest.exists():
                raise ValueError('V5 manifest missing: V6 refuses unmanaged source')
            prev = json.loads(prev_manifest.read_text('utf-8'))
            if digest(original) != prev.get('installed_sha256'):
                raise ValueError('Current V5 source differs from saved digest; refusing patch')
            patched = patch_source(current).encode('utf-8')
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(original)
            os.chmod(backup, 0o600)
            state = {'previous_sha256': digest(original), 'installed_sha256': digest(patched),
                     'source': str(source), 'backup': str(backup)}
            try:
                atomic_write(source, patched)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(patched):
                    atomic_write(source, original)
                raise
            print('Installed V6 screenshot continuation (upstream approval/policy unchanged).')
            print('Backup:', backup)
            return 0
        if not installed or not manifest.exists() or not backup.exists():
            raise ValueError('V6 source/manifest/backup needed for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if digest(original) != state.get('installed_sha256'):
            raise ValueError('V6 source was edited; rollback refused')
        prev = backup.read_bytes()
        if digest(prev) != state.get('previous_sha256'):
            raise ValueError('V6 backup digest mismatch')
        atomic_write(source, prev)
        manifest.unlink()
        backup.unlink()
        print('V6 rolled back to exact V5 bytes')
        return 0
    except (OSError, ValueError, SyntaxError, KeyError, json.JSONDecodeError) as error:
        print('ERROR:', error, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
'@
    Invoke-OdysseusPython $code @($Mode, $ProjectDir)
}
function Invoke-AgentRuntimeV7([string]$Mode = 'status') {
    $code = @'
#!/usr/bin/env python3
"""Zarzysseus V7: treat an HTTP(S) URL as web content, never a workspace path.

The installed upstream Odysseus _looks_like_workspace_coding_request() matched
`//example.com` in `https://example.com` as a Unix path. With a workspace set,
that activated Terminus-only routing and stripped Playwright browser MCP tools.
This patch changes just the workspace detector; it does not grant any tool,
change enabled/disabled MCP settings, or override approval/security decisions.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

MARKER = '# ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7'
PREV_MARKER = '# ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6'
FUNCTION_ANCHOR = 'def _looks_like_workspace_coding_request(text: str) -> bool:'
OLD_RETURN = '    return bool(_WORKSPACE_CODE_ACTION_RE.search(text) and _WORKSPACE_CODE_TARGET_RE.search(text))'
NEW_RETURN = '''    # ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7
    # URLs are web resources, not local /paths. The upstream path regex can
    # match //example.com inside https://example.com and incorrectly replace
    # the browser toolset with workspace/terminal tools when a workspace exists.
    # Preserve normal mixed URL + genuine repo/file tasks (they still match).
    _zar_non_url_targets_v7 = re.sub(
        r"(?i)\\b(?:https?://|www\\.)[^\\s\\\"'<>`]+", " ", text
    )
    return bool(
        _WORKSPACE_CODE_ACTION_RE.search(_zar_non_url_targets_v7)
        and _WORKSPACE_CODE_TARGET_RE.search(_zar_non_url_targets_v7)
    )'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def locations(root: Path):
    root = root.expanduser().resolve()
    b = root / 'data' / 'local' / 'patch-backups'
    return (root / 'src' / 'agent_loop.py', b / 'agent-url-workspace-v7.before.py',
            b / 'agent-url-workspace-v7.json', b / 'agent-explicit-screenshot-v6.json')


def patch_source(source: str) -> str:
    if MARKER in source:
        raise ValueError('V7 is already installed')
    if PREV_MARKER not in source:
        raise ValueError('Install V6 before V7')
    if source.count(FUNCTION_ANCHOR) != 1 or source.count(OLD_RETURN) != 1:
        raise ValueError('Upstream workspace detector changed; refuse unguarded patch')
    fn = source.index(FUNCTION_ANCHOR)
    end = source.find('\ndef ', fn + len(FUNCTION_ANCHOR))
    if end == -1:
        raise ValueError('Cannot safely locate detector end')
    if OLD_RETURN not in source[fn:end]:
        raise ValueError('Expected return not within workspace detector')
    patched = source.replace(OLD_RETURN, NEW_RETURN, 1)
    ast.parse(patched)
    return patched


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-v7-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def smoke(source: str) -> None:
    tree = ast.parse(source)
    required = ['_looks_like_workspace_coding_request']
    regexes = ['_WORKSPACE_CODE_ACTION_RE', '_WORKSPACE_CODE_TARGET_RE']
    nodes = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
             and n.name in required]
    assert len(nodes) == 1
    assign_nodes = [n for n in tree.body if isinstance(n, ast.Assign) and any(
        getattr(t, 'id', '') in regexes for t in n.targets)]
    assert len(assign_nodes) == 2
    import re
    env = {'re': re}
    exec(compile(ast.Module(body=assign_nodes + nodes, type_ignores=[]), 'agent_loop.py', 'exec'), env)
    detector = env[required[0]]
    cases = [
        ('Open https://example.com, take a screenshot, display it here, and describe the page.', False),
        ('Open https://example.com using the browser, take a screenshot', False),
        ('Visit https://github.com and take a screenshot of the UI', False),
        ('Open www.example.com in the browser and screenshot it', False),
        ('Open https://example.com/docs/guide with Playwright', False),
        ('Open /etc/hosts and inspect the file', True),
        ('Read ~/project/file.py and fix it', True),
        ('Fix this project bug', True),
        ('Open https://example.com and edit my project file', True),
        ('Inspect this workspace repo', True),
    ]
    for request, expected in cases:
        got = bool(detector(request))
        if got != expected:
            raise AssertionError(f'{request!r}: got workspace={got}; expected {expected}')
    print('PASS: browser URLs no longer trigger Terminus workspace mode')
    print('PASS: local files, repo edits, mixed web+file tasks retain workspace routing')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('operation', choices=('install', 'status', 'rollback', 'smoke'))
    ap.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = ap.parse_args(argv)
    source, backup, manifest, prev_manifest = locations(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Agent source missing: {source}')
        original = source.read_bytes()
        current = original.decode('utf-8')
        installed = MARKER in current
        if args.operation == 'status':
            print('V7 URL/workspace routing fix:', 'installed' if installed else 'not installed')
            print('V7 backup manifest:', 'present' if manifest.exists() else 'missing')
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Installed V7 differs from saved checksum')
            return 0 if installed else 1
        if args.operation == 'smoke':
            smoke(current if installed else patch_source(current))
            return 0
        if args.operation == 'install':
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('V7 modified since installation; refusing to overwrite')
                print('    [ready] V7 URL/workspace routing fix already installed')
                return 0
            if backup.exists() or manifest.exists():
                raise ValueError('Stale V7 manifest or backup; reconcile before installation')
            if not prev_manifest.is_file():
                raise ValueError('V6 backup manifest missing; refusing unmanaged upgrade')
            prev = json.loads(prev_manifest.read_text('utf-8'))
            if prev.get('installed_sha256') != digest(original):
                raise ValueError('Current agent source differs from recorded V6; refusing patch')
            patched = patch_source(current).encode('utf-8')
            smoke(patched.decode('utf-8'))
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(original)
            os.chmod(backup, 0o600)
            state = {'previous_sha256': digest(original), 'installed_sha256': digest(patched),
                     'source': str(source), 'backup': str(backup)}
            try:
                atomic_write(source, patched)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(patched):
                    atomic_write(source, original)
                raise
            print('Installed V7 URL-as-path routing repair (tool policy and approvals unchanged)')
            print('Backup:', backup)
            return 0
        if not installed or not manifest.is_file() or not backup.is_file():
            raise ValueError('V7 source/manifest/backup required for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if digest(original) != state.get('installed_sha256'):
            raise ValueError('Installed V7 source was edited; refusing rollback')
        old = backup.read_bytes()
        if digest(old) != state.get('previous_sha256'):
            raise ValueError('V7 backup digest mismatch')
        atomic_write(source, old)
        manifest.unlink()
        backup.unlink()
        print('V7 rolled back to exact V6 source')
        return 0
    except (OSError, ValueError, AssertionError, SyntaxError, UnicodeError, KeyError, json.JSONDecodeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
'@
    Invoke-OdysseusPython $code @($Mode, $ProjectDir)
}
function Invoke-AgentRuntimeV8([string]$Mode = 'status') {
    $code = @'
#!/usr/bin/env python3
"""Zarzysseus V8: schema-valid screenshot continuation without fabricated model calls.

Patches V6's approved navigation -> screenshot continuation to accept only
known safe mandatory screenshot parameters. Rejects unexpected mandatory
fields. Preserves Odysseus permissions/approvals, output handling, and rollback.

Usage: python zarzysseus_screenshot_schema_v8.py install|status|rollback|smoke CHECKOUT
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

MARKER = '# ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8'
PREV_MARKER = '# ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7'
PREVIOUS_BRANCH_START = '                if _zar_required_v6 == []:\n'
PREVIOUS_BRANCH_END = '            elif _zar_nav_ok_v6 and not _zar_shot_already_v6:\n'
NEW_BRANCH = '''                # ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8
                # Some installed Playwright MCP adapters mark image format,
                # scale or fullPage as required although the API has defaults.
                # Supply safe values ONLY when their actual JSON schema agrees.
                # Never supply filename: leaving it unset lets Playwright return
                # the screenshot inline as image data instead of just a path.
                _zar_args_v8 = {}
                _zar_defaults_v8 = {"type": "png", "scale": "css", "fullPage": False}
                _zar_expected_types_v8 = {"type": "string", "scale": "string", "fullPage": "boolean"}
                _zar_properties_v8 = _zar_params_v6.get("properties", {}) if isinstance(_zar_params_v6, dict) else None
                _zar_invalid_v8 = not (
                    isinstance(_zar_required_v6, list)
                    and all(isinstance(k, str) for k in _zar_required_v6)
                    and isinstance(_zar_properties_v8, dict)
                )
                if not _zar_invalid_v8:
                    for _zar_field_v8 in _zar_required_v6:
                        if _zar_field_v8 not in _zar_defaults_v8:
                            _zar_invalid_v8 = True
                            break
                        _zar_prop_v8 = _zar_properties_v8.get(_zar_field_v8)
                        _zar_value_v8 = _zar_defaults_v8[_zar_field_v8]
                        if not isinstance(_zar_prop_v8, dict):
                            _zar_invalid_v8 = True
                            break
                        _zar_field_type_v8 = _zar_prop_v8.get("type")
                        if _zar_field_type_v8 not in (None, _zar_expected_types_v8[_zar_field_v8]):
                            _zar_invalid_v8 = True
                            break
                        _zar_enum_v8 = _zar_prop_v8.get("enum")
                        if _zar_enum_v8 is not None and (
                            not isinstance(_zar_enum_v8, list) or _zar_value_v8 not in _zar_enum_v8
                        ):
                            _zar_invalid_v8 = True
                            break
                        _zar_args_v8[_zar_field_v8] = _zar_value_v8
                if not _zar_invalid_v8:
                    _zar_explicit_call_v6 = [{
                        "id": "zarzysseus_explicit_screenshot_v8",
                        "name": _zar_shot_v6,
                        "arguments": json.dumps(_zar_args_v8, separators=(",", ":")),
                    }]
                    _zar_blocks_v6, _zar_native_v6, _zar_converted_v6 = _resolve_tool_blocks(
                        round_response, _zar_explicit_call_v6, round_num, is_api_model=True,
                    )
                    if len(_zar_blocks_v6) == 1 and _zar_native_v6 and _zar_blocks_v6[0].tool_type == _zar_shot_v6:
                        native_tool_calls = _zar_explicit_call_v6
                        tool_blocks = _zar_blocks_v6
                        used_native = _zar_native_v6
                        converted_calls = _zar_converted_v6
                        logger.info(
                            "[zarzysseus-agent-v8] queued schema-valid screenshot via upstream executor args=%s",
                            sorted(_zar_args_v8),
                        )
                    else:
                        logger.warning("[zarzysseus-agent-v8] screenshot converter refused; no action queued")
                else:
                    logger.warning(
                        "[zarzysseus-agent-v8] unsupported mandatory screenshot fields: %s",
                        _zar_required_v6,
                    )
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def locations(root: Path):
    root = root.expanduser().resolve()
    b = root / 'data' / 'local' / 'patch-backups'
    return root / 'src' / 'agent_loop.py', b / 'agent-screenshot-schema-v8.before.py', b / 'agent-screenshot-schema-v8.json', b / 'agent-url-workspace-v7.json'


def patch_source(source: str) -> str:
    if MARKER in source:
        raise ValueError('V8 already installed')
    if PREV_MARKER not in source:
        raise ValueError('Install V7 before V8')
    if source.count(PREVIOUS_BRANCH_START) != 1 or source.count(PREVIOUS_BRANCH_END) != 1:
        raise ValueError('V6 screenshot branch changed; refusing unguarded patch')
    start = source.index(PREVIOUS_BRANCH_START)
    end = source.index(PREVIOUS_BRANCH_END)
    if end <= start or end - start > 6000 or '# ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' not in source[:start]:
        raise ValueError('Unexpected screenshot branch range')
    old_segment = source[start:end]
    if '_zar_explicit_call_v6' not in old_segment or 'screenshot schema requires arguments' not in old_segment:
        raise ValueError('Unexpected V6 screenshot branch body')
    patched = source[:start] + NEW_BRANCH + source[end:]
    ast.parse(patched)
    return patched


def choose_safe_arguments(required, properties):
    """Test oracle matching the deliberately conservative runtime logic."""
    defaults = {'type': 'png', 'scale': 'css', 'fullPage': False}
    types = {'type': 'string', 'scale': 'string', 'fullPage': 'boolean'}
    if not isinstance(required, list) or not all(isinstance(k, str) for k in required) or not isinstance(properties, dict):
        return None
    args = {}
    for field in required:
        if field not in defaults or not isinstance(properties.get(field), dict):
            return None
        prop = properties[field]
        if prop.get('type') not in (None, types[field]):
            return None
        enum = prop.get('enum')
        if enum is not None and (not isinstance(enum, list) or defaults[field] not in enum):
            return None
        args[field] = defaults[field]
    return args


def smoke(source: str) -> None:
    if MARKER not in source:
        source = patch_source(source)
    ast.parse(source)
    props = {'type': {'type':'string','enum':['png','jpeg']}, 'scale':{'type':'string','enum':['css','device']}, 'fullPage':{'type':'boolean'}, 'filename':{'type':'string'}}
    assert choose_safe_arguments([], props) == {}
    assert choose_safe_arguments(['type'], props) == {'type':'png'}
    assert choose_safe_arguments(['type','scale','fullPage'], props) == {'type':'png','scale':'css','fullPage':False}
    assert choose_safe_arguments(['filename'], props) is None
    assert choose_safe_arguments(['type'], {'type': {'type':'string','enum':['jpeg']}}) is None
    assert choose_safe_arguments(['type'], {'type': {'type':'integer'}}) is None
    assert choose_safe_arguments(['unexpected'], props) is None
    assert 'and _approved_result_injected' in source
    assert 'and bool(_zar_approved_browser_followup_v5)' in source
    assert 'and not _zar_shot_already_v6' in source
    assert 'and e.get("exit_code") == 0' in source
    assert '_resolve_tool_blocks(' in source
    assert '"filename":' not in NEW_BRANCH
    print('PASS: safe required screenshot fields -> schema-valid, no filename')
    print('PASS: unknown/unsafe mandatory fields are rejected')
    print('PASS: approved successful navigation, one-shot guard, upstream executor preserved')


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-v8-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('install','status','rollback','smoke'))
    parser.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = parser.parse_args(argv)
    source, backup, manifest, prev_manifest = locations(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Agent source missing: {source}')
        original = source.read_bytes()
        current = original.decode('utf-8')
        installed = MARKER in current
        if args.operation == 'status':
            print('V8 screenshot schema arguments:', 'installed' if installed else 'not installed')
            print('V8 backup manifest:', 'present' if manifest.is_file() else 'missing')
            if installed and (not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original)):
                raise ValueError('Installed V8 source differs from recorded digest')
            return 0 if installed else 1
        if args.operation == 'smoke':
            smoke(current)
            return 0
        if args.operation == 'install':
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Existing V8 source was modified; installation refused')
                print('    [ready] V8 screenshot schema repair already installed')
                return 0
            if manifest.exists() or backup.exists():
                raise ValueError('Stale V8 manifest or backup; reconcile first')
            if not prev_manifest.is_file():
                raise ValueError('V7 backup manifest missing')
            prev = json.loads(prev_manifest.read_text('utf-8'))
            if digest(original) != prev.get('installed_sha256'):
                raise ValueError('Current V7 source differs from saved digest; refusing patch')
            patched = patch_source(current).encode('utf-8')
            smoke(patched.decode('utf-8'))
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(original)
            os.chmod(backup, 0o600)
            state = {'previous_sha256':digest(original), 'installed_sha256':digest(patched), 'source':str(source), 'backup':str(backup)}
            try:
                atomic_write(source, patched)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(patched):
                    atomic_write(source, original)
                raise
            print('Installed V8 schema-aware screenshot continuation (approvals unchanged)')
            print('Backup:', backup)
            return 0
        if not installed or not manifest.is_file() or not backup.is_file():
            raise ValueError('V8 source/manifest/backup required for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if digest(original) != state.get('installed_sha256'):
            raise ValueError('Current source was edited since V8 install; rollback refused')
        old = backup.read_bytes()
        if digest(old) != state.get('previous_sha256'):
            raise ValueError('V8 backup digest mismatch')
        atomic_write(source, old)
        manifest.unlink()
        backup.unlink()
        print('V8 rolled back to exact V7 source')
        return 0
    except (OSError, ValueError, AssertionError, SyntaxError, UnicodeError, KeyError, json.JSONDecodeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
'@
    Invoke-OdysseusPython $code @($Mode, $ProjectDir)
}
function Agent-Doctor {
    Write-Host '=== Zarzysseus Agent Doctor (read-only) ===' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Warn 'Odysseus environment missing: install first.'; return }
    try { Invoke-AgentReliability 'status' } catch { Warn $_.Exception.Message }
    try { Invoke-AgentRuntimeV3 'status' } catch { Warn $_.Exception.Message }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5' -Quiet) { Write-Host 'V4 compact fallback: retained beneath V5' }
    else { try { Invoke-AgentRuntimeV4 'status' } catch { Warn $_.Exception.Message } }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' -Quiet) { Write-Host 'V5 approved continuation: retained beneath V6' }
    else { try { Invoke-AgentRuntimeV5 'status' } catch { Warn $_.Exception.Message } }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7' -Quiet) { Write-Host 'V6 screenshot continuation: retained beneath V7' }
    else { try { Invoke-AgentRuntimeV6 'status' } catch { Warn $_.Exception.Message } }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'srcgent_loop.py') -SimpleMatch 'ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8' -Quiet) { Write-Host 'V7 URL/workspace routing: retained beneath V8' }
    else { try { Invoke-AgentRuntimeV7 'status' } catch { Warn $_.Exception.Message } }
    try { Invoke-AgentRuntimeV8 'status' } catch { Warn $_.Exception.Message }
    try { Invoke-AgentRuntimeV8 'smoke' } catch { Warn $_.Exception.Message }
    try { Invoke-AgentRuntimeV7 'smoke' } catch { Warn $_.Exception.Message }
    $sourceFile = Join-Path $ProjectDir 'src\agent_loop.py'
    if ((Test-Path -LiteralPath $sourceFile) -and (Select-String -LiteralPath $sourceFile -SimpleMatch 'ZARZYSSEUS_AGENT_RELIABILITY_V2' -Quiet)) {
        Invoke-AgentReliability 'smoke'
        Invoke-AgentRuntimeV3 'smoke'
    } else { Warn 'Agent repair missing; run agent-repair.' }
    if (Have 'npx') { Okay 'Node/npx available' } else { Warn 'Node/npx missing: browser MCP cannot start.' }
    Write-Host 'For browser server status: mcp-health or Odysseus Settings > MCP.'
    Write-Host 'This is a routing simulation, not a live LLM/browser session.'
}
function Invoke-AgentReliabilityAuto {
    if (Test-Path -LiteralPath (Join-Path $StateDir 'agent-routing.disabled')) {
        Warn 'Agent auto-repair disabled after rollback. Run agent-repair to re-enable.'
        return
    }
    Invoke-AgentReliability 'install'
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py')) -or -not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4' -Quiet)) { Invoke-AgentRuntimeV3 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5' -Quiet)) { Invoke-AgentRuntimeV4 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' -Quiet)) { Invoke-AgentRuntimeV5 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7' -Quiet)) { Invoke-AgentRuntimeV6 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'srcgent_loop.py') -SimpleMatch 'ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8' -Quiet)) { Invoke-AgentRuntimeV7 'install' }
    Invoke-AgentRuntimeV8 'install'
}
function Agent-Repair {
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Fail 'Install Odysseus first.' }
    try { Install-QwenToolFocus } catch { Warn "Qwen tool focus: $($_.Exception.Message)" }
    Invoke-AgentReliability 'install'
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4' -Quiet)) { Invoke-AgentRuntimeV3 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5' -Quiet)) { Invoke-AgentRuntimeV4 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' -Quiet)) { Invoke-AgentRuntimeV5 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7' -Quiet)) { Invoke-AgentRuntimeV6 'install' }
    if (-not (Select-String -LiteralPath (Join-Path $ProjectDir 'srcgent_loop.py') -SimpleMatch 'ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8' -Quiet)) { Invoke-AgentRuntimeV7 'install' }
    Invoke-AgentRuntimeV8 'install'
    Remove-Item -LiteralPath (Join-Path $StateDir 'agent-routing.disabled') -Force -ErrorAction SilentlyContinue
    try { Ensure-NodePlaywrightMcp } catch { Warn "Browser MCP provisioning: $($_.Exception.Message)" }
    if (Current-Process) { Stop-App; Start-App }
    Invoke-AgentReliability 'smoke'
}
function Agent-Rollback {
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'srcgent_loop.py') -SimpleMatch 'ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8' -Quiet) { Invoke-AgentRuntimeV8 'rollback' }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7' -Quiet) { Invoke-AgentRuntimeV7 'rollback' }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' -Quiet) { Invoke-AgentRuntimeV6 'rollback' }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_APPROVED_BROWSER_CONTINUATION_V5' -Quiet) { Invoke-AgentRuntimeV5 'rollback' }
    if (Select-String -LiteralPath (Join-Path $ProjectDir 'src\agent_loop.py') -SimpleMatch 'ZARZYSSEUS_COMPACT_BROWSER_FALLBACK_V4' -Quiet) { Invoke-AgentRuntimeV4 'rollback' }
    Invoke-AgentRuntimeV3 'rollback'
    Invoke-AgentReliability 'rollback'
    Set-Content -LiteralPath (Join-Path $StateDir 'agent-routing.disabled') -Value 'Rollback requested; leave agent reliability patch disabled until explicit agent-repair.' -Encoding UTF8
    if (Current-Process) { Stop-App; Start-App }
}

function Tool-Health {
    Write-Host '=== Zarzysseus / Odysseus Tool Health ==='
    Write-Host "Project checkout: $ProjectDir"
    Write-Host "ChromaDB heartbeat: $(if (Chroma-Ready) { 'ready' } else { 'UNREACHABLE' })"
    Write-Host "Ollama API: $(if (Ollama-Ready) { 'ready' } else { 'UNREACHABLE' })"
    Workspace-Default -Status
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Warn 'Odysseus venv missing.'; return }
    $code = @'
from urllib.parse import urlparse
from core.database import SessionLocal, ModelEndpoint
from src.settings import get_setting
from pathlib import Path
with SessionLocal() as db:
    for ep in db.query(ModelEndpoint).all():
        url = urlparse(ep.base_url or "")
        if url.hostname in ("localhost", "127.0.0.1") and url.port == 11434 and url.path.rstrip("/") == "/v1":
            print(f"Ollama endpoint {ep.id}: tools={ep.supports_tools!r}, host={url.hostname}")
for key in ("default_model", "default_endpoint_id", "utility_model", "utility_endpoint_id", "teacher_model", "teacher_enabled"):
    print(f"{key}: {get_setting(key, None)!r}")
p = Path("src/agent_loop.py")
print("Qwen explicit-tool/skill/MCP focus:", "installed" if p.is_file() and ("ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4" in p.read_text(encoding="utf-8") or "ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V3" in p.read_text(encoding="utf-8") or "ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V2" in p.read_text(encoding="utf-8") or "ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V1" in p.read_text(encoding="utf-8")) else "not installed")
print("Note: user/session routing can differ from global settings.")
'@
    Invoke-OdysseusPython $code @()
}
function Install-QwenToolFocus {
    if (-not $QwenFocusEnabled) { Warn 'Qwen focus disabled by ZARZYSSEUS_QWEN_TOOL_FOCUS=0'; return }
    $sourceFile = Join-Path $ProjectDir 'src\agent_loop.py'
    if (-not (Test-Path -LiteralPath $sourceFile)) { Fail 'Odysseus agent_loop.py not found.' }
    $backup = Join-Path $ProjectDir 'data\local\patch-backups'
    $code = @'
import pathlib, sys, re, datetime
source = pathlib.Path(sys.argv[1]); backup_dir = pathlib.Path(sys.argv[2])
original = source.read_text(encoding="utf-8")
marker_v4 = "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4"
markers_old = ["# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V3", "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V2", "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V1"]
if marker_v4 in original:
    print("    [ready] Qwen explicit-tool + skill + MCP routing focus V4 already installed")
    raise SystemExit(0)
focus_block = r'''            # ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4
            # Qwen schema routing guard. It narrows already-authorized schemas;
            # all original execution approval/security remains in force.
            try:
                _zar_first_round = (round_num == 1)
            except NameError:
                _zar_first_round = False
            if "qwen" in (model or "").lower() and schemas:
                import re as _zar_re
                import pathlib as _zar_pathlib
                _zar_text = _last_user or ""
                _zar_focused_request = False
                if _zar_first_round:
                    _zar_match = _zar_re.match(r"^\s*(?:call|use|execute|run)\s+(?:the\s+)?[`\"']?([A-Za-z_][A-Za-z0-9_]*)[`\"']?(?=\s|[.,:;!?]|$)", _zar_text, _zar_re.I)
                    if _zar_match:
                        _zar_name = _zar_match.group(1)
                        _zar_focused = [schema for schema in schemas if schema.get("function", {}).get("name") == _zar_name]
                        if len(_zar_focused) == 1:
                            schemas = _zar_focused; _zar_focused_request = True
                            logger.info("[zarzysseus-tool-focus] first-round Qwen explicit tool=%s", _zar_name)
                if _zar_first_round and not _zar_focused_request:
                    _zar_skill_name = None
                    _zar_skill = _zar_re.match(r"^\s*/([A-Za-z0-9][A-Za-z0-9_-]*)\b", _zar_text)
                    if _zar_skill:
                        _zar_skill_name = _zar_skill.group(1)
                    else:
                        _zar_embedded = _zar_re.search(r"(?ms)^--- BEGIN SKILL ---\s*.*?^name\s*:\s*[\"']?([A-Za-z0-9][A-Za-z0-9_-]*)[\"']?\s*$", _zar_text)
                        if _zar_embedded: _zar_skill_name = _zar_embedded.group(1)
                    if _zar_skill_name:
                        try:
                            from services.memory.skills import SkillsManager as _ZarSkillsManager
                            from src.constants import DATA_DIR as _ZAR_DATA_DIR
                            _zar_sm = _ZarSkillsManager(_ZAR_DATA_DIR)
                            _zar_entry = next((x for x in _zar_sm.load(owner=owner) if str(x.get("name") or "") == _zar_skill_name), None)
                            if _zar_entry:
                                _zar_required = set(str(x) for x in (_zar_entry.get("requires_toolsets") or []) if x)
                                if not _zar_required:
                                    _zar_path = _zar_pathlib.Path(str(_zar_entry.get("path") or "")); _zar_dir = _zar_path.parent if _zar_path.name.lower() == "skill.md" else _zar_path
                                    if any((_zar_dir / n).is_file() for n in ("run.py","run.sh","run.bash","run.ps1","runner.py","runner.sh")): _zar_required.add("bash")
                                _zar_skill_schemas = [schema for schema in schemas if schema.get("function", {}).get("name") in _zar_required]
                                if _zar_skill_schemas:
                                    schemas = _zar_skill_schemas; _zar_focused_request = True
                                    logger.info("[zarzysseus-skill-focus] first-round Qwen skill=%s tools=%s", _zar_skill_name, sorted(_zar_required))
                        except Exception as _zar_exc:
                            logger.debug("[zarzysseus-skill-focus] lookup skipped: %s", _zar_exc)
                if not _zar_focused_request:
                    _zar_low = _zar_text.lower()
                    _zar_browser_intent = bool(_zar_re.search(r"\b(browser|browse|website|webpage|web page|navigate|click|screenshot|playwright|puppeteer|tradingview)\b|https?://", _zar_low))
                    _zar_browser_code_intent = bool(_zar_re.search(r"\b(javascript|puppeteer|playwright script|browser automation|automate (?:the )?browser|run code in (?:the )?browser|browser_run_code_unsafe)\b", _zar_low))
                    _zar_before = len(schemas)
                    if not _zar_browser_intent:
                        schemas = [schema for schema in schemas if not str(schema.get("function", {}).get("name") or "").startswith("mcp__builtin_browser__")]
                    elif not _zar_browser_code_intent:
                        schemas = [schema for schema in schemas if str(schema.get("function", {}).get("name") or "") != "mcp__builtin_browser__browser_run_code_unsafe"]
                    if len(schemas) != _zar_before:
                        logger.info("[zarzysseus-mcp-focus] Qwen browser schemas %s -> %s (browser_intent=%s code_intent=%s)", _zar_before, len(schemas), _zar_browser_intent, _zar_browser_code_intent)
            return _filter_route_tool_schemas(schemas)
'''
if any(m in original for m in markers_old):
    pat = re.compile(r"            # ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V(?:1|2|3)\n.*?            return _filter_route_tool_schemas\(schemas\)\n", re.S)
    if len(pat.findall(original)) != 1:
        print("    [skipped] Existing V1/V2/V3 focus patch shape is unexpected; source not modified."); raise SystemExit(2)
    updated = pat.sub(lambda _m: focus_block, original, count=1)
else:
    needle = "            return _filter_route_tool_schemas(schemas)\n\n        wants_mcp"
    if original.count(needle) != 1:
        print("    [skipped] Upstream agent tool-schema builder changed; source not modified."); raise SystemExit(2)
    updated = original.replace(needle, focus_block + "\n        wants_mcp", 1)
compile(updated, str(source), "exec")
backup_dir.mkdir(parents=True, exist_ok=True)
backup_file = backup_dir / ("agent_loop.py." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
backup_file.write_text(original, encoding="utf-8")
source.write_text(updated, encoding="utf-8")
print(f"    [installed] Qwen explicit-tool + skill + MCP routing focus V4; backup: {backup_file}")
'@
    Invoke-OdysseusPython $code @($sourceFile, $backup)
    if (Current-Process) {
        Say 'Restarting managed Odysseus after guarded local source patch...'
        Stop-App; Start-App
    } else { Warn 'Restart any manually started Odysseus process for the patch to take effect.' }
}
function Install-DirectToolJsonRecovery {
    if (-not $DirectToolJsonRecovery) { Warn 'Compact tool-JSON recovery disabled by ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY=0'; return }
    $target = Join-Path $ProjectDir 'src\tool_parsing.py'
    if (-not (Test-Path -LiteralPath $target)) { Warn 'src/tool_parsing.py not found; compact tool-JSON recovery skipped.'; return }
    if (Select-String -LiteralPath $target -SimpleMatch 'ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY_V1' -Quiet) { Okay 'Compact {name, arguments} tool-call recovery already installed.'; return }
    $backup = Join-Path $ProjectDir 'data\local\patch-backups'
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $code = @'
from pathlib import Path
from datetime import datetime
import py_compile, shutil, sys, tempfile

target=Path(sys.argv[1]); backups=Path(sys.argv[2]); marker='ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY_V1'
src=target.read_text(encoding='utf-8')
if marker in src:
    print('    [ready] Compact tool-JSON recovery already installed.')
    raise SystemExit(0)
helper='''\n# ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY_V1\ndef _zarzysseus_direct_tool_json_payload(text: str):\n    \"\"\"Strictly recover a whole-response {name, arguments} tool call.\n\n    This is intentionally narrower than generic JSON parsing: the entire assistant\n    response must be one JSON object (optionally wrapped in one JSON fence), the\n    key set is restricted, and the existing canonical converter still decides\n    whether the named native/MCP tool is executable.\n    \"\"\"\n    if not isinstance(text, str):\n        return None\n    raw=text.strip()\n    if raw.startswith(\"```\") and raw.endswith(\"```\"):\n        lines=raw.splitlines()\n        if len(lines) < 3 or lines[0].strip().lower() not in (\"```json\", \"```\") or lines[-1].strip() != \"```\":\n            return None\n        raw=\"\\n\".join(lines[1:-1]).strip()\n    if not (raw.startswith(\"{\") and raw.endswith(\"}\")):\n        return None\n    try:\n        obj=json.loads(raw)\n    except (json.JSONDecodeError, TypeError):\n        return None\n    if not isinstance(obj, dict) or set(obj) - {\"name\", \"arguments\", \"id\", \"type\", \"tool_call_id\"}:\n        return None\n    name=obj.get(\"name\")\n    args=obj.get(\"arguments\", {})\n    if not isinstance(name, str) or not name.strip():\n        return None\n    if isinstance(args, str):\n        try:\n            args=json.loads(args)\n        except (json.JSONDecodeError, TypeError):\n            return None\n    if not isinstance(args, dict):\n        return None\n    return {\"name\": name.strip(), \"arguments\": args}\n\n'''
anchor='def _parse_raw_openai_tool_call_json(text: str) -> Optional[ToolBlock]:\n'
if src.count(anchor) != 1:
    print('    [skip] Upstream raw tool-call parser shape changed; source left untouched.')
    raise SystemExit(2)
src=src.replace(anchor, helper+anchor, 1)
old='''def _parse_raw_openai_tool_call_json(text: str) -> Optional[ToolBlock]:\n    if not isinstance(text, str) or '"function"' not in text:\n        return None\n'''
new='''def _parse_raw_openai_tool_call_json(text: str) -> Optional[ToolBlock]:\n    direct = _zarzysseus_direct_tool_json_payload(text)\n    if direct is not None:\n        return _raw_openai_tool_call_to_block({\"function\": direct, \"type\": \"function\"})\n    if not isinstance(text, str) or '"function"' not in text:\n        return None\n'''
if old not in src:
    print('    [skip] Upstream _parse_raw_openai_tool_call_json guard changed; source left untouched.')
    raise SystemExit(2)
src=src.replace(old,new,1)
strip_anchor='''def _strip_raw_openai_tool_call_json(text: str) -> str:\n    \"\"\"Strip raw JSON tool calls such as {\"function\": {...}, \"type\": \"function\"}.\n'''
idx=src.find(strip_anchor)
if idx < 0:
    print('    [skip] Upstream raw tool-call stripping function changed; source left untouched.')
    raise SystemExit(2)
needle='''    if not isinstance(text, str) or '"function"' not in text:\n        return text\n'''
guard_idx=src.find(needle, idx)
if guard_idx < 0:
    print('    [skip] Upstream raw tool-call stripping guard changed; source left untouched.')
    raise SystemExit(2)
replacement='''    direct = _zarzysseus_direct_tool_json_payload(text)\n    if direct is not None and _raw_openai_tool_call_to_block({\"function\": direct, \"type\": \"function\"}):\n        return \"\"\n    if not isinstance(text, str) or '"function"' not in text:\n        return text\n'''
src=src[:guard_idx]+replacement+src[guard_idx+len(needle):]
backups.mkdir(parents=True, exist_ok=True)
stamp=datetime.now().strftime('%Y%m%d-%H%M%S')
backup=backups/f'tool_parsing.py.{stamp}.direct-json.bak'
shutil.copy2(target, backup)
with tempfile.NamedTemporaryFile('w',encoding='utf-8',delete=False,dir=str(target.parent),prefix='.tool_parsing.',suffix='.py') as f:
    f.write(src); tmp=Path(f.name)
try:
    py_compile.compile(str(tmp), doraise=True)
    tmp.replace(target)
finally:
    if tmp.exists(): tmp.unlink()
print(f'    [installed] Compact tool-JSON recovery -> {target}')
print(f'    [backup] {backup}')
'@
    Invoke-OdysseusPython $code @($target,$backup)
}

function Provision-SkillMcpServers {
    if (-not $SkillMcpAutoInstall) { Warn 'Skill MCP auto-provisioning disabled by ZARZYSSEUS_SKILL_MCP_AUTO_INSTALL=0'; return }
    $root = Join-Path $ProjectDir 'data\skills\imported'
    if (-not (Test-Path -LiteralPath $root)) { Warn 'No imported skills directory yet; no skill MCP declarations to provision.'; return }
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Warn 'Odysseus Python environment missing; skill MCP provisioning deferred.'; return }
    Ensure-McpPythonRuntime
    $code = @'
from __future__ import annotations
from pathlib import Path
import asyncio, hashlib, json, os, re, shutil, stat, subprocess, sys

project=Path(sys.argv[1]).expanduser().resolve(); root=Path(sys.argv[2]).expanduser().resolve()
sys.path.insert(0,str(project)); os.chdir(project)
from core.database import SessionLocal, McpServer
from services.memory.skill_format import parse_frontmatter

SAFE_NAME=re.compile(r'[^A-Za-z0-9_]+')
VAR_PATTERNS=(re.compile(r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$'),re.compile(r'^%([A-Za-z_][A-Za-z0-9_]*)%$'))
launch_root=project/'data'/'local'/'skill-mcp'; launch_root.mkdir(parents=True,exist_ok=True)
launcher_code='''from pathlib import Path\nimport json, os, subprocess, sys\ncfg=json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))\nenv=os.environ.copy()\nfor k,v in (cfg.get("env") or {}).items():\n    s=str(v)\n    if s.startswith("${") and s.endswith("}"):\n        n=s[2:-1]; s=os.environ.get(n,"")\n    elif s.startswith("%") and s.endswith("%") and len(s)>2:\n        n=s[1:-1]; s=os.environ.get(n,"")\n    env[str(k)]=s\ncmd=[cfg["command"], *[str(x) for x in cfg.get("args",[])]]\nraise SystemExit(subprocess.call(cmd,cwd=cfg["cwd"],env=env))\n'''

def slug(v:str)->str:
    s=SAFE_NAME.sub('_',str(v).strip()).strip('_').lower()
    return s[:36] or 'server'

def mcp_declarations(fm):
    value=None
    for key in ('mcpServers','mcpservers','mcp_servers','mcp-servers'):
        if key in fm: value=fm.get(key); break
    if not value: return []
    if isinstance(value,dict):
        return [(str(k),v if isinstance(v,dict) else {}) for k,v in value.items()]
    if isinstance(value,list):
        out=[]
        for i,item in enumerate(value):
            if not isinstance(item,dict): continue
            name=item.get('name') or item.get('id') or f'server-{i+1}'
            spec=dict(item); spec.pop('name',None); spec.pop('id',None); out.append((str(name),spec))
        return out
    return []

def expand_command(command:str, skill_dir:Path):
    command=str(command or '').strip()
    if not command: return None
    if any(c in command for c in '\n\r;&|`><'):
        return None
    p=Path(command)
    if '/' in command or '\\' in command:
        if not p.is_absolute(): p=(skill_dir/p).resolve()
        else: p=p.resolve()
        try: p.relative_to(skill_dir.resolve())
        except ValueError:
            # Absolute system executables are allowed only if they are exactly what PATH resolves.
            resolved=shutil.which(command)
            if not resolved or Path(resolved).resolve()!=p: return None
        return str(p) if p.exists() else None
    if command.lower() in ('python','python3','py'):
        return sys.executable
    resolved=shutil.which(command)
    return resolved

def missing_placeholders(env):
    missing=[]
    for _k,v in (env or {}).items():
        s=str(v)
        for pat in VAR_PATTERNS:
            m=pat.match(s)
            if m and not os.environ.get(m.group(1)):
                missing.append(m.group(1))
    return sorted(set(missing))

def update_requires(md:Path, names:list[str]):
    if not names: return False
    text=md.read_text(encoding='utf-8',errors='replace')
    m=re.match(r'\A---\s*\n(.*?)\n---\s*\n?',text,re.S)
    if not m: return False
    front=m.group(1); body=text[m.end():]
    req=re.search(r'(?ms)^requires_toolsets\s*:\s*(.*?)(?=^[A-Za-z_][A-Za-z0-9_-]*\s*:|\Z)',front)
    existing=[]
    if req:
        existing=re.findall(r'mcp__[A-Za-z0-9_]+__[A-Za-z0-9_.:-]+|[A-Za-z_][A-Za-z0-9_-]*',req.group(0).split(':',1)[1])
    merged=[]
    for x in existing+names:
        if x and x not in merged: merged.append(x)
    if merged==existing: return False
    block='requires_toolsets:\n'+''.join(f'  - {x}\n' for x in merged)
    if req: front=front[:req.start()]+block+front[req.end():]
    else: front=front.rstrip()+'\n'+block
    md.write_text('---\n'+front.rstrip()+'\n---\n\n'+body.lstrip('\n'),encoding='utf-8')
    return True

async def probe_stdio(command,args,env,timeout=35):
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    params=StdioServerParameters(command=command,args=[str(x) for x in args],env=env or None)
    async def go():
        async with stdio_client(params) as (read,write):
            async with ClientSession(read,write) as session:
                await session.initialize(); result=await session.list_tools()
                return [str(t.name) for t in (result.tools or []) if getattr(t,'name',None)]
    return await asyncio.wait_for(go(),timeout=timeout)

checked=declared=ready=disabled=failed=metadata_changed=0
for md in sorted(root.glob('*/SKILL.md')):
    checked+=1
    text=md.read_text(encoding='utf-8',errors='replace')
    try: fm,_body=parse_frontmatter(text)
    except Exception as e:
        print(f'    [warning] {md.parent.name}: frontmatter parse failed: {e}'); failed+=1; continue
    decls=mcp_declarations(fm)
    if not decls: continue
    skill_name=str(fm.get('name') or md.parent.name); skill_dir=md.parent.resolve(); qualified=[]
    for declared_name,spec in decls:
        declared+=1
        transport=str(spec.get('transport') or ('http' if spec.get('url') else 'stdio')).strip().lower()
        if transport in ('streamable-http','streamable_http'): transport='http'
        server_id=('skill_'+slug(skill_name)+'_'+slug(declared_name))[:90]
        display=f'skill:{skill_name}:{declared_name}'
        row_args=None; row_env=None; row_url=None; row_command=None; enabled=True; tools=[]
        # V9: no new unreviewed MCP server is downloaded, launched or registered.
        approval_key=f'{md.parent.name}/{declared_name}'
        fp=hashlib.sha256(json.dumps(spec,sort_keys=True,default=str,separators=(',',':')).encode()).hexdigest()
        approval_path=project/'data'/'local'/'zarzysseus-skill-v9-approvals.json'
        try:
            approval_data=json.loads(approval_path.read_text(encoding='utf-8'))
            if not isinstance(approval_data,dict) or approval_data.get('version')!=1:
                approval_data={'version':1,'approved':{},'legacy':{}}
        except (OSError,ValueError,AttributeError):
            approval_data={'version':1,'approved':{},'legacy':{}}
        approved=(approval_data.get('approved') or {}).get(approval_key)==fp
        if not approved:
            with SessionLocal() as db:
                existing=db.get(McpServer,server_id)
                legacy_enabled=bool(existing and existing.is_enabled)
            legacy=approval_data.get('legacy') or {}
            if not isinstance(legacy,dict): legacy={}
            if legacy_enabled and approval_key not in legacy and approval_key not in (approval_data.get('approved') or {}):
                # One-time trust snapshot of a server that was already enabled before V9.
                # Further edits to this skill MCP declaration must be reviewed again.
                legacy[approval_key]=fp
                approval_data['legacy']=legacy
                approval_path.parent.mkdir(parents=True,exist_ok=True)
                tmp=approval_path.with_suffix('.tmp')
                tmp.write_text(json.dumps(approval_data,indent=2,sort_keys=True)+'\n',encoding='utf-8')
                os.chmod(tmp,0o600)
                tmp.replace(approval_path)
            legacy_allowed=legacy_enabled and legacy.get(approval_key)==fp
            if not legacy_allowed:
                disabled+=1
                print(f'    [approval-required] {skill_name}/{declared_name}: V9 skills-setup must approve this MCP declaration first')
                continue
            print(f'    [legacy-config] {skill_name}/{declared_name}: retaining previously enabled unchanged server')
        if transport=='stdio':
            command=spec.get('command'); args=spec.get('args') or []
            if isinstance(command,list) and command:
                args=list(command[1:])+list(args if isinstance(args,list) else [args]); command=command[0]
            if isinstance(args,str): args=[args]
            if not isinstance(args,list): args=[]
            env=spec.get('env') or {}; env=env if isinstance(env,dict) else {}
            resolved=expand_command(str(command or ''),skill_dir)
            missing=missing_placeholders(env)
            if not resolved:
                print(f'    [disabled] {skill_name}/{declared_name}: executable not found or unsafe: {command!r}')
                enabled=False; disabled+=1
            elif missing:
                print(f'    [disabled] {skill_name}/{declared_name}: missing environment variable(s): {", ".join(missing)}')
                enabled=False; disabled+=1
            else:
                base=Path(resolved).name.lower()
                if base in ('npx','npx.cmd') and '-y' not in args and '--yes' not in args:
                    args=['-y',*args]
                if base in ('node','node.exe') and (skill_dir/'package.json').is_file() and not (skill_dir/'node_modules').exists():
                    npm=shutil.which('npm') or shutil.which('npm.cmd')
                    if npm:
                        print(f'    [install] {skill_name}/{declared_name}: npm dependencies')
                        subprocess.run([npm,'install','--no-audit','--no-fund'],cwd=skill_dir,check=False)
                if Path(resolved).resolve()==Path(sys.executable).resolve() and (skill_dir/'requirements.txt').is_file():
                    print(f'    [install] {skill_name}/{declared_name}: Python requirements')
                    subprocess.run([sys.executable,'-m','pip','install','-r',str(skill_dir/'requirements.txt')],cwd=skill_dir,check=False)
                cfg_dir=launch_root/slug(skill_name)/slug(declared_name); cfg_dir.mkdir(parents=True,exist_ok=True)
                launcher=cfg_dir/'launcher.py'; cfg=cfg_dir/'launcher.json'
                launcher.write_text(launcher_code,encoding='utf-8')
                cfg.write_text(json.dumps({'cwd':str(skill_dir),'command':resolved,'args':args,'env':env},indent=2),encoding='utf-8')
                try: os.chmod(cfg,stat.S_IRUSR|stat.S_IWUSR)
                except OSError: pass
                row_command=sys.executable; row_args=json.dumps([str(launcher),str(cfg)])
                probe_env=os.environ.copy()
                try:
                    tools=asyncio.run(probe_stdio(row_command,[str(launcher),str(cfg)],probe_env))
                    ready+=1
                    print(f'    [ready] {skill_name}/{declared_name}: {len(tools)} MCP tool(s) discovered')
                except Exception as e:
                    enabled=False; failed+=1
                    print(f'    [warning] {skill_name}/{declared_name}: MCP handshake failed: {type(e).__name__}: {e}')
        elif transport in ('sse','http'):
            url=str(spec.get('url') or '').strip()
            remote_env=spec.get('env') or spec.get('headers') or {}; remote_env=remote_env if isinstance(remote_env,dict) else {}
            missing=missing_placeholders(remote_env)
            if not re.match(r'^https?://',url):
                enabled=False; disabled+=1; print(f'    [disabled] {skill_name}/{declared_name}: invalid/missing MCP URL')
            elif missing:
                enabled=False; disabled+=1; print(f'    [disabled] {skill_name}/{declared_name}: missing environment/header variable(s): {", ".join(missing)}')
            else:
                row_url=url; row_env=json.dumps(remote_env) if remote_env else None; ready+=1
                print(f'    [configured] {skill_name}/{declared_name}: remote {transport} MCP URL registered; tools discover on Odysseus connect')
        else:
            enabled=False; disabled+=1; print(f'    [disabled] {skill_name}/{declared_name}: unsupported transport {transport!r}')
        with SessionLocal() as db:
            row=db.get(McpServer,server_id)
            if row is None:
                row=McpServer(id=server_id); db.add(row)
            row.name=display; row.transport=transport; row.command=row_command; row.args=row_args; row.env=row_env; row.url=row_url; row.is_enabled=bool(enabled)
            db.commit()
        if enabled and tools:
            qualified.extend(f'mcp__{server_id}__{t}' for t in tools)
    if update_requires(md,qualified):
        metadata_changed+=1
        print(f'    [repaired] {skill_name}: added {len(qualified)} discovered qualified MCP tool requirement(s)')
print(f'    [skill-mcp] checked={checked} declarations={declared} ready={ready} disabled={disabled} failed={failed} metadata_repaired={metadata_changed}')
if failed:
    print('    [note] Failed MCP declarations remain configured disabled; rerun skills-mcp-fix after fixing dependencies/secrets.')
'@
    Invoke-OdysseusPython $code @($ProjectDir,$root)
}

function Ensure-McpPythonRuntime {
    if (-not $McpAutoRepair) { Warn 'MCP auto-repair disabled by ZARZYSSEUS_MCP_AUTO_REPAIR=0'; return }
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $python)) { Fail 'Odysseus Python environment is required for MCP repair.' }
    $legacy = $false
    $mcpDir = Join-Path $ProjectDir 'mcp_servers'
    if (Test-Path -LiteralPath $mcpDir) {
        $paths = @(Get-ChildItem -LiteralPath $mcpDir -Filter '*.py' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        if ($paths.Count -gt 0) {
            $hit = Select-String -Path $paths -Pattern '@server\.(list_tools|call_tool)\(' -Quiet
            if ($hit) { $legacy = $true }
        }
    }
    $version = (& $python -c "import importlib.metadata as m; print(m.version('mcp'))" 2>$null)
    if ($LASTEXITCODE -ne 0) { $version = 'missing' }
    $major = -1
    if ($version -match '^(\d+)') { $major = [int]$Matches[1] }
    if ($legacy -and ($version -eq 'missing' -or $major -ge 2 -or $major -lt 0)) {
        Say 'Repairing Odysseus MCP SDK compatibility (legacy built-ins require mcp<2)'
        Invoke-Checked $python @('-m','pip','install','--upgrade','mcp<2')
        $version = (& $python -c "import importlib.metadata as m; print(m.version('mcp'))")
    } elseif (-not $legacy -and $version -eq 'missing') {
        Say 'Installing MCP Python SDK required by Odysseus'
        Invoke-Checked $python @('-m','pip','install','--upgrade','mcp')
        $version = (& $python -c "import importlib.metadata as m; print(m.version('mcp'))")
    }
    Okay "MCP Python SDK $version"
}
function Ensure-NodePlaywrightMcp {
    if (-not (Have 'npx')) {
        Ensure-Winget
        Say 'Installing Node.js LTS for the built-in Playwright MCP server'
        & winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Fail 'Node.js installation failed.' }
        Refresh-UserPath
    }
    if (-not (Have 'npx')) { Fail 'npx is still missing. Reopen PowerShell and rerun mcp-setup.' }
    Say 'Caching @playwright/mcp for Odysseus built-in browser MCP'
    & npx -y '@playwright/mcp@latest' --version
    if ($LASTEXITCODE -ne 0) { Fail '@playwright/mcp setup failed.' }
    Say 'Installing/checking Playwright Chromium browser for MCP'
    & npx -y playwright install chromium
    if ($LASTEXITCODE -ne 0) { Fail 'Playwright Chromium setup failed.' }
}
function FreeMcp-Venv { return (Join-Path $ProjectDir 'data\local\freemcp-venv') }
function FreeMcp-Exe { return (Join-Path (FreeMcp-Venv) 'Scripts\freemcp.exe') }
function FreeMcp-RegistryDir {
    if ($env:FREEMCP_REGISTRY_DIR) { return $env:FREEMCP_REGISTRY_DIR }
    return (Join-Path $ProjectDir 'data\local\freemcp-registry')
}
function Test-FreeMcpCli { return (Test-Path -LiteralPath (FreeMcp-Exe)) }
function Ensure-FreeMcp {
    if (-not $FreeMcpAutoInstall) { Warn 'FreeMCP registry sync disabled by ZARZYSSEUS_FREEMCP_AUTO_INSTALL=0'; return }
    if (-not (Have 'git')) { Fail 'Git is required to sync the FreeMCP registry.' }
    $dir = FreeMcp-RegistryDir
    $parent = Split-Path -Parent $dir
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Say 'Checking/updating freemcp.space public registry cache'
    if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
        & git -C $dir fetch --quiet --depth 1 origin main
        if ($LASTEXITCODE -eq 0) { & git -C $dir reset --quiet --hard FETCH_HEAD }
        if ($LASTEXITCODE -ne 0) { Warn 'Could not refresh FreeMCP registry; keeping the existing cache.' }
    } else {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        & git clone --quiet --depth 1 $FreeMcpRegistryRepo $dir
        if ($LASTEXITCODE -ne 0) { Fail 'Unable to clone the FreeMCP registry.' }
    }
    $servers = Join-Path $dir 'servers'
    if (-not (Test-Path -LiteralPath $servers)) { Fail 'FreeMCP registry cache is missing servers\.' }
    $count = @(Get-ChildItem -LiteralPath $servers -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    Okay "FreeMCP registry cache: $count machine-readable server entries"
    if (Test-FreeMcpCli) {
        $ver = (& (FreeMcp-Exe) --version 2>$null)
        if ($ver) { Okay ("Optional FreeMCP CLI also present: " + $ver) } else { Okay 'Optional FreeMCP CLI also present' }
    } else {
        Write-Host '    [note] freemcp.space documents a beta pip CLI, but freemcp-cli may not actually be published on PyPI yet; registry discovery works without it.'
    }
}
function FreeMcp-Status {
    Write-Host '=== FreeMCP / freemcp.space status ===' -ForegroundColor Cyan
    $dir = FreeMcp-RegistryDir
    $servers = Join-Path $dir 'servers'
    if (Test-Path -LiteralPath $servers) {
        $count = @(Get-ChildItem -LiteralPath $servers -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        $commit = (& git -C $dir rev-parse --short HEAD 2>$null)
        if (-not $commit) { $commit = 'unknown' }
        Write-Host "Registry cache: ready ($count entries, commit $commit)"
        Write-Host "Registry path:  $dir"
    } else {
        Write-Host 'Registry cache: missing (run freemcp-setup or mcp-setup)'
    }
    if (Test-FreeMcpCli) {
        $ver = (& (FreeMcp-Exe) --version 2>$null)
        Write-Host "Optional CLI: $ver"
    } else {
        Write-Host 'Optional CLI: unavailable/not installed; discovery uses the synced public registry instead.'
    }
    Write-Host 'Website: https://freemcp.space/'
}
function FreeMcp-Search([string]$query) {
    if([string]::IsNullOrWhiteSpace($query)){Fail "Usage: zarzysseus.ps1 freemcp-search 'query'"}
    $dir = FreeMcp-RegistryDir
    $servers = Join-Path $dir 'servers'
    if (-not (Test-Path -LiteralPath $servers)) { Ensure-FreeMcp }
    $terms = @($query.ToLowerInvariant().Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries))
    $rows = New-Object System.Collections.Generic.List[object]
    foreach($file in Get-ChildItem -LiteralPath $servers -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try { $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop } catch { continue }
        $hay = $raw.ToLowerInvariant()
        $match = $true
        foreach($t in $terms){ if(-not $hay.Contains($t)){ $match=$false; break } }
        if(-not $match){ continue }
        try { $d = $raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $slug = if($d.slug){[string]$d.slug}else{$file.BaseName}
        $title = if($d.title){[string]$d.title}elseif($d.name){[string]$d.name}else{$slug}
        $desc = if($d.description){([string]$d.description -replace "`r?`n",' ').Trim()}else{''}
        $relative = $file.FullName.Substring($servers.Length).TrimStart('\','/')
        $category = ($relative -split '[\\/]')[0]
        $repo = ''
        if($d.git_url){$repo=[string]$d.git_url}elseif($d.repository){if($d.repository -is [string]){$repo=[string]$d.repository}elseif($d.repository.url){$repo=[string]$d.repository.url}}
        $remote = ''
        if($d.url){$remote=[string]$d.url}elseif($d.endpoint){$remote=[string]$d.endpoint}elseif($d.remotes -and $d.remotes.Count -gt 0 -and $d.remotes[0].url){$remote=[string]$d.remotes[0].url}
        $score=0; foreach($t in $terms){$score += ([regex]::Matches($hay,[regex]::Escape($t))).Count}
        $rows.Add([pscustomobject]@{Score=$score;Title=$title;Category=$category;Slug=$slug;Description=$desc;Repo=$repo;Remote=$remote}) | Out-Null
    }
    $rows = @($rows | Sort-Object @{Expression='Score';Descending=$true},Title | Select-Object -First 25)
    if($rows.Count -eq 0){ Warn "No FreeMCP registry matches for: $query"; return }
    Write-Host "FreeMCP registry matches for: $query (showing up to 25)`n" -ForegroundColor Cyan
    $i=0
    foreach($r in $rows){
        $i++; Write-Host (("{0,2}. {1}  [{2}]" -f $i,$r.Title,$r.Category))
        if($r.Description){$d=$r.Description;if($d.Length -gt 220){$d=$d.Substring(0,220)};Write-Host "    $d"}
        if($r.Remote){Write-Host "    MCP: $($r.Remote)"}
        if($r.Repo){Write-Host "    Source: $($r.Repo)"}
        Write-Host "    FreeMCP: https://freemcp.space/featured/$($r.Slug)"
    }
}
function FreeMcp-Login {
    if (Test-FreeMcpCli) {
        & (FreeMcp-Exe) login
        if($LASTEXITCODE -ne 0){Fail 'FreeMCP login failed.'}
        return
    }
    Warn 'The documented freemcp-cli package is not currently available in this environment/PyPI index. Registry search does not need a login.'
    Write-Host 'For account/deployment features, use: https://freemcp.space/'
}
function Show-McpHealth {
    Write-Host '=== Zarzysseus MCP health ===' -ForegroundColor Cyan
    $python = Get-VenvPython
    if (Test-Path -LiteralPath $python) {
        $version = (& $python -c "import importlib.metadata as m; print(m.version('mcp'))" 2>$null); if($LASTEXITCODE -ne 0){$version='missing'}
        Write-Host "MCP Python SDK: $version"
    } else { Write-Host 'MCP Python SDK: Odysseus venv not installed' }
    $npxState = if (Have 'npx') { (Get-Command npx).Source } else { 'missing' }
    Write-Host "Node/npx: $npxState"
    $freeDir = FreeMcp-RegistryDir
    $freeServers = Join-Path $freeDir 'servers'
    if(Test-Path -LiteralPath $freeServers){
        $freeCount = @(Get-ChildItem -LiteralPath $freeServers -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        Write-Host "FreeMCP registry cache: ready ($freeCount entries)"
    } else { Write-Host 'FreeMCP registry cache: missing (run freemcp-setup or mcp-setup)' }
    if(Test-FreeMcpCli){ Write-Host "FreeMCP optional CLI: $(& (FreeMcp-Exe) --version 2>$null)" } else { Write-Host 'FreeMCP optional CLI: unavailable; registry discovery does not require it' }
    $agent = Join-Path $ProjectDir 'src\agent_loop.py'
    $focus='not installed'; if((Test-Path -LiteralPath $agent) -and (Select-String -LiteralPath $agent -SimpleMatch 'ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4' -Quiet)){$focus='V4 installed'}
    Write-Host "Qwen MCP routing guard: $focus"
    $mcpScript=Join-Path $ProjectDir 'scripts\odysseus-mcp'
    if(Test-Path -LiteralPath $mcpScript){ Write-Host 'Configured MCP servers can also be viewed in Odysseus Settings → MCP.' }
}
function Setup-Mcp {
    if (-not (Test-Path -LiteralPath (Get-VenvPython))) { Install-Stack; return }
    Ensure-McpPythonRuntime
    Ensure-NodePlaywrightMcp
    try { Ensure-FreeMcp } catch { Warn "FreeMCP registry sync: $($_.Exception.Message)" }
    Install-QwenToolFocus
    try { Invoke-AgentReliabilityAuto } catch { Warn "Agent web-tool routing repair: $($_.Exception.Message)" }
    Install-DirectToolJsonRecovery
    try { Provision-SkillMcpServers } catch { Warn "Skill MCP provisioning: $($_.Exception.Message)" }
    Okay 'MCP runtime, browser cache, FreeMCP registry, compact tool-JSON recovery, skill-declared MCP servers, and Qwen routing guard checked.' 
}
function Mcp-Menu {
    while($true){
        Write-Host "`nMCP / FREEMCP" -ForegroundColor Cyan
        Write-Host '1  Set up / repair MCP stack'
        Write-Host '2  MCP health'
        Write-Host '3  Sync/update FreeMCP registry'
        Write-Host '4  FreeMCP registry status'
        Write-Host '5  Search FreeMCP public registry'
        Write-Host '6  FreeMCP login'
        Write-Host '7  Install/upgrade Qwen MCP routing guard'
        Write-Host '8  Provision MCP servers declared by installed skills'
        Write-Host '9  Repair compact local-model tool JSON execution'
        Write-Host '0  Back'
        switch(Read-Host 'Choose'){
            '1'{Setup-Mcp};'2'{Show-McpHealth};'3'{Ensure-FreeMcp};'4'{FreeMcp-Status};
            '5'{$q=Read-Host 'Search query';if($q){FreeMcp-Search $q}};'6'{FreeMcp-Login};'7'{Install-QwenToolFocus};'8'{Provision-SkillMcpServers};'9'{Install-DirectToolJsonRecovery};'0'{return};default{Warn 'Unknown choice.'}
        }
    }
}

# --- End integration repairs ---

function Install-Stack {
    Ensure-Project
    # Only a committed install runs automatic Docker provisioning; never TUI startup.
    if (-not (Ensure-Docker)) { Warn 'Docker setup incomplete; installing Odysseus anyway. ChromaDB will need docker-setup after Desktop is ready.' }
    $python = Ensure-Venv
    Say 'Installing native Odysseus requirements (no full Windows OS upgrade)'
    Invoke-Checked $python @('-m','pip','install','--upgrade','pip')
    Invoke-Checked $python @('-m','pip','install','-r',(Join-Path $ProjectDir 'requirements.txt'))
    Ensure-McpPythonRuntime
    try { Ensure-NodePlaywrightMcp } catch { Warn "Playwright MCP setup: $($_.Exception.Message)" }
    try { Ensure-FreeMcp } catch { Warn "FreeMCP registry sync: $($_.Exception.Message)" }
    Say 'Running upstream Odysseus setup'
    Push-Location $ProjectDir
    try { Invoke-Checked $python @('setup.py') }
    finally { Pop-Location }
    try { Install-ChatContinuityFix } catch { Warn "Chat continuity repair: $($_.Exception.Message)" }
    try { Install-CookbookFixes } catch { Warn "Cookbook reliability repair: $($_.Exception.Message)" }
    try { Install-DirectToolJsonRecovery } catch { Warn "Compact tool-JSON recovery: $($_.Exception.Message)" }
    try { Provision-SkillMcpServers } catch { Warn "Skill MCP provisioning: $($_.Exception.Message)" }
    try { Workspace-Default } catch { Warn "Default workspace setup: $($_.Exception.Message)" }
    try { Ensure-Chromadb } catch { Warn "ChromaDB startup: $($_.Exception.Message)" }
    if (Ollama-Ready) { try { Sync-Ollama } catch { Warn "Ollama sync: $($_.Exception.Message)" } }
    try { Repair-SkillRuntimeMetadata } catch { Warn "Skill runtime metadata repair: $($_.Exception.Message)" }
    try { Install-QwenToolFocus } catch { Warn "Qwen skill/tool focus patch: $($_.Exception.Message)" }
    try { Invoke-AgentReliabilityAuto } catch { Warn "Agent web-tool routing repair: $($_.Exception.Message)" }
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
    try { Install-ChatContinuityFix } catch { Warn "Chat continuity repair: $($_.Exception.Message)" }
    try { Install-CookbookFixes } catch { Warn "Cookbook reliability repair: $($_.Exception.Message)" }
    try { Install-DirectToolJsonRecovery } catch { Warn "Compact tool-JSON recovery: $($_.Exception.Message)" }
    try { Provision-SkillMcpServers } catch { Warn "Skill MCP provisioning: $($_.Exception.Message)" }
    try { Workspace-Default } catch { Warn "Default workspace setup: $($_.Exception.Message)" }
    try { Ensure-Chromadb } catch { Warn "ChromaDB startup: $($_.Exception.Message)" }
    if (Ollama-Ready) { try { Sync-Ollama } catch { Warn "Ollama sync: $($_.Exception.Message)" } }
    try { Invoke-AgentReliabilityAuto } catch { Warn "Agent web-tool routing repair: $($_.Exception.Message)" }
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
        Okay 'Ollama already serving on localhost:11434'; Sync-Ollama; return
    } catch { }
    $app = (Get-Command ollama).Source
    Start-Process -FilePath $app -ArgumentList @('serve') -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
    Okay 'Ollama launch requested; check http://localhost:11434/api/tags.'
    if (Ollama-Ready) { Sync-Ollama }
}
# The curated tobestyledintro model is an Ollama registry entry even though its
# namespace/model spelling looks like a Hugging Face repo. Check this before
# invoking any Hugging Face setup/download or installing prerequisites.
function Test-OllamaRegistryModel([string]$model) {
    if ([string]::IsNullOrWhiteSpace($model)) { return $false }
    return [bool]($model.Trim() -match '^tobestyledintro/qwen3[.]8-9b-distill(?::[A-Za-z0-9][A-Za-z0-9._-]*)?$')
}
function Install-Model([string]$model) {
    $model = ($model + '').Trim()
    if (-not $model) { Fail 'Supply a model ID. For an Ollama model use ollama-pull MODEL.' }
    if (Test-OllamaRegistryModel $model) { Pull-Ollama $model; return }
    if ($model -match '^[\w./:-]+$' -and $model -notmatch '^[\w.-]+/[\w.-]+$') {
        Pull-Ollama $model; return
    }
    # Other namespaced IDs are ambiguous. Keep existing Hub-model behavior;
    # users can explicitly choose ollama-pull for any other Ollama registry ID.
    Download-Hub $model
}
function Pull-Ollama([string]$model) {
    if (-not $model -or $model -notmatch '^[\w./:-]+$') { Fail 'Supply a valid Ollama model tag.' }
    Start-Ollama
    Invoke-Checked 'ollama' @('pull',$model)
    Sync-Ollama $model
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
    # Guard BEFORE venv/HF installation, token handling or snapshot_download.
    # A Hugging Face access token cannot make an Ollama registry ID a Hub repo.
    if (Test-OllamaRegistryModel $repo) {
        Fail "'$repo' is an Ollama registry model, not a Hugging Face repo. Use: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-pull '$repo'"
    }
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
      [pscustomobject]@{Family='Normal';Type='Text';Name='Qwen3.8 9B Distill (Ollama)';Id='tobestyledintro/qwen3.8-9b-distill';Source='Ollama';Params='9B (name)';Size='check Ollama tag'},
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
                # Important: no Docker/OS/model installation before this confirmation.
                if (-not (Ensure-Docker)) { Warn 'Docker not ready yet. Models can still download; ChromaDB may remain unavailable.' }
                try { Ensure-Chromadb } catch { Warn "ChromaDB startup: $($_.Exception.Message)" }
                foreach($model in $items | Where-Object {$selected.Contains($_.Id)}) {
                    try { if($model.Source -eq 'Ollama' -or (Test-OllamaRegistryModel $model.Id)){Pull-Ollama $model.Id}else{Download-Hub $model.Id} }
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
    Repair-SkillRuntimeMetadata
    Install-QwenToolFocus
}
function Repair-SkillRuntimeMetadata {
    $imported = Join-Path $ProjectDir 'data\skills\imported'
    $python = Get-VenvPython
    if (-not (Test-Path -LiteralPath $imported)) { Warn 'No imported Odysseus skills directory yet.'; return }
    if (-not (Test-Path -LiteralPath $python)) { Warn 'Odysseus Python environment missing.'; return }
    $code = @'
from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]); data_dir=root.parent.parent
owner=''
auth_path=data_dir/'auth.json'
try:
    auth=json.loads(auth_path.read_text(encoding='utf-8'))
    users=auth.get('users',{}) if isinstance(auth,dict) else {}
    if isinstance(users,dict):
        admins=[str(k) for k,v in users.items() if isinstance(v,dict) and v.get('is_admin')]
        owner=(admins[0] if admins else (next(iter(users),'') if users else '')).strip()
except Exception:
    pass
changed=[]; checked=0
for md in sorted(root.glob('*/SKILL.md')):
    checked+=1
    text=md.read_text(encoding='utf-8',errors='replace')
    m=re.match(r'\A---\s*\n(.*?)\n---\s*\n?',text,re.S)
    if not m: continue
    front=m.group(1); body=text[m.end():]; folder=md.parent
    runnable=any((folder/n).is_file() for n in ('run.py','run.sh','run.bash','run.ps1','runner.py','runner.sh')) or any((folder/n).is_dir() for n in ('scripts','bin','tools'))
    commandish=bool(re.search(r'(?:execute with|run\.py|run\.sh|run\.ps1|python(?:3)?\s+[^\n`]+\.py|bash\s+[^\n`]+\.sh|pwsh\s+[^\n`]+\.ps1)',body,re.I))
    aliases={'bash':'bash','shell':'bash','run_shell':'bash','read':'read_file','read_file':'read_file','write':'write_file','write_file':'write_file','edit':'edit_file','edit_file':'edit_file','glob':'glob','grep':'grep','python':'python','webfetch':'web_fetch','web_fetch':'web_fetch','websearch':'web_search','web_search':'web_search','askuser':'ask_user','ask_user':'ask_user'}
    desired=[]
    if runnable or commandish: desired.append('bash')
    allowed=re.search(r'(?ms)^allowed[-_]tools\s*:\s*(.*?)(?=^[A-Za-z_][A-Za-z0-9_-]*\s*:|\Z)',front)
    if allowed:
        for tok in re.findall(r'[A-Za-z_][A-Za-z0-9_-]*',allowed.group(0).split(':',1)[1]):
            mapped=aliases.get(tok.lower())
            if mapped and mapped not in desired: desired.append(mapped)
    modified=False
    if desired:
        req=re.search(r'(?ms)^requires_toolsets\s*:\s*(.*?)(?=^[A-Za-z_][A-Za-z0-9_-]*\s*:|\Z)',front)
        existing=[]
        if req:
            for tok in re.findall(r'[A-Za-z_][A-Za-z0-9_-]*',req.group(0).split(':',1)[1]):
                if tok not in existing: existing.append(tok)
        merged=existing+[x for x in desired if x not in existing]
        if merged!=existing:
            block='requires_toolsets:\n'+''.join(f'  - {x}\n' for x in merged)
            if req: front=front[:req.start()]+block+front[req.end():]
            else: front=front.rstrip()+'\n'+block
            modified=True
    if owner and not re.search(r'(?m)^owner\s*:',front):
        front=front.rstrip()+f'\nowner: {owner}\n'
        modified=True
    if modified:
        md.write_text('---\n'+front.rstrip()+'\n---\n\n'+body.lstrip('\n'),encoding='utf-8')
        changed.append(md.parent.name)
print(f'[skill-runtime] checked={checked} repaired={len(changed)} owner={owner or "unresolved"}')
for n in changed: print(f'[repaired] {n}')
'@
    Invoke-OdysseusPython $code @($imported)
    try { Install-DirectToolJsonRecovery } catch { Warn "Compact tool-JSON recovery: $($_.Exception.Message)" }
    try { Provision-SkillMcpServers } catch { Warn "Skill MCP provisioning: $($_.Exception.Message)" }
}

function Fave-Skills {
    $base=Join-Path $ProjectDir 'data\skills\imported'
    $python=Get-VenvPython
    if (-not (Test-Path $python)){Fail 'Install the Odysseus stack first to install executable favorite skills.'}
    Invoke-Checked $python @('-m','pip','install','python-docx','openpyxl','python-pptx','pypdf','reportlab','Pillow','ruff','faster-whisper')
    if (-not (Have 'ffmpeg')) { Warn 'FFmpeg is not present; the video skill will report unavailable until FFmpeg is installed.' }
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $skills=@(
        [pscustomobject]@{Name='zarzysseus-fave-office';Group='office';Description='Local Word, spreadsheet, slides, and PDF creation/extraction.'},
        [pscustomobject]@{Name='zarzysseus-fave-photo-edit';Group='photo-edit';Description='Local image resize/edit operations with Pillow.'},
        [pscustomobject]@{Name='zarzysseus-fave-video-edit';Group='video-edit';Description='Local video trimming/transcoding with FFmpeg.'},
        [pscustomobject]@{Name='zarzysseus-fave-scripting';Group='scripting';Description='Local Python/PowerShell script syntax checking and linting.'},
        [pscustomobject]@{Name='zarzysseus-fave-transcription';Group='transcription';Description='Local speech-to-text with Faster-Whisper.'}
    )
    foreach($sk in $skills){
        $dir=Join-Path $base $sk.Name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $runner=Join-Path $dir 'run.py'
        $pythonForSkill=$python.Replace('\','/')
        $runnerForSkill=$runner.Replace('\','/')
        $md=@"
---
name: $($sk.Name)
description: $($sk.Description)
version: 1.0.0
category: imported
requires_toolsets:
  - bash
tags:
  - zarzysseus
  - executable
status: published
source: imported
---

# $($sk.Name)

$($sk.Description)

## Execution
Use the native ``bash`` tool to execute this checked local runner. Do not stop at a plan, and do not substitute browser/MCP tools unless this skill explicitly requires them.

Check first:
``$pythonForSkill $runnerForSkill --check``

Then run the appropriate flags shown by ``--help``. Verify the requested output exists before reporting success.
"@
        Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $md -Encoding UTF8
        $runnerCode=@'
import argparse,subprocess,sys,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--input');p.add_argument('--output');p.add_argument('--text');p.add_argument('--file');p.add_argument('--width',type=int);p.add_argument('--start',type=float,default=0);p.add_argument('--duration',type=float)
a=p.parse_args(); group=__GROUP__
if group=='office':
 import docx,pptx,openpyxl,pypdf,reportlab
 if a.check: print('Office document libraries ready'); raise SystemExit(0)
 if not a.output: p.error('--output required')
 out=Path(a.output); out.parent.mkdir(parents=True,exist_ok=True)
 if a.input:
  inp=Path(a.input)
  if out.suffix.lower()!='.txt': p.error('extraction output must be .txt')
  if inp.suffix.lower()=='.docx': content='\n'.join(q.text for q in docx.Document(inp).paragraphs)
  elif inp.suffix.lower()=='.pdf': content='\n'.join(pg.extract_text() or '' for pg in pypdf.PdfReader(inp).pages)
  elif inp.suffix.lower()=='.pptx': content='\n'.join(shape.text for slide in pptx.Presentation(inp).slides for shape in slide.shapes if getattr(shape,'has_text_frame',False))
  elif inp.suffix.lower()=='.xlsx':
   wb=openpyxl.load_workbook(inp,read_only=True,data_only=True); content='\n'.join('\t'.join('' if c is None else str(c) for c in row) for sh in wb for row in sh.values); wb.close()
  else: p.error('supported input: .docx/.pdf/.pptx/.xlsx')
  out.write_text(content+'\n',encoding='utf-8')
 else:
  if a.text is None: p.error('provide --text or --input')
  lines=a.text.splitlines() or [a.text]
  if out.suffix.lower()=='.docx':
   d=docx.Document(); [d.add_paragraph(x) for x in lines]; d.save(out)
  elif out.suffix.lower()=='.xlsx':
   wb=openpyxl.Workbook();ws=wb.active
   for x in lines: ws.append(x.split('\t'))
   wb.save(out)
  elif out.suffix.lower()=='.pptx':
   deck=pptx.Presentation()
   for x in lines:
    slide=deck.slides.add_slide(deck.slide_layouts[5]); slide.shapes.title.text=x
   deck.save(out)
  elif out.suffix.lower()=='.pdf':
   from reportlab.pdfgen import canvas
   page=canvas.Canvas(str(out)); y=page._pagesize[1]-72
   for x in lines:
    if y<72: page.showPage(); y=page._pagesize[1]-72
    page.drawString(72,y,x[:120]); y-=18
   page.save()
  else: p.error('supported output: .docx/.xlsx/.pptx/.pdf')
 print(out)
elif group=='photo-edit':
 from PIL import Image
 if a.check: print('Pillow ready'); raise SystemExit(0)
 if not a.input or not a.output: p.error('--input and --output required')
 with Image.open(a.input) as im:
  if a.width: im=im.resize((a.width,round(im.height*a.width/im.width)))
  im.save(a.output)
 print(a.output)
elif group=='video-edit':
 if not shutil.which('ffmpeg'): raise SystemExit('ffmpeg missing')
 if a.check: print('FFmpeg ready'); raise SystemExit(0)
 if not a.input or not a.output: p.error('--input and --output required')
 cmd=['ffmpeg','-hide_banner','-y','-ss',str(a.start),'-i',a.input]
 if a.duration: cmd+=['-t',str(a.duration)]
 subprocess.run(cmd+['-c:v','libx264','-c:a','aac',a.output],check=True); print(a.output)
elif group=='scripting':
 if a.check: print('Scripting runtime ready'); raise SystemExit(0)
 if not a.file: p.error('--file required')
 if a.file.lower().endswith('.py'): subprocess.run([sys.executable,'-m','py_compile',a.file],check=True)
 elif a.file.lower().endswith('.ps1'):
  ps=shutil.which('pwsh') or shutil.which('powershell')
  if not ps: raise SystemExit('PowerShell executable missing')
  quoted=a.file.replace("'","''")
  subprocess.run([ps,'-NoProfile','-Command',f"[void][scriptblock]::Create((Get-Content -Raw -LiteralPath '{quoted}'))"],check=True)
 else: p.error('supported: .py/.ps1')
 print(a.file)
else:
 from faster_whisper import WhisperModel
 if a.check: print('Faster-Whisper ready'); raise SystemExit(0)
 if not a.file: p.error('--file required')
 model=WhisperModel('tiny',device='cpu',compute_type='int8'); segments,_=model.transcribe(a.file); text='\n'.join(s.text.strip() for s in segments)
 if a.output: Path(a.output).write_text(text+'\n',encoding='utf-8'); print(a.output)
 else: print(text)
'@
        $runnerCode=$runnerCode.Replace('__GROUP__',("'"+$sk.Group+"'"))
        Set-Content -LiteralPath $runner -Value $runnerCode -Encoding UTF8
        & $python $runner --check
        if($LASTEXITCODE -ne 0){Warn "Runtime check failed: $($sk.Name)"}else{Okay "Executable Odysseus skill installed: $($sk.Name)"}
    }
    Repair-SkillRuntimeMetadata
    Install-QwenToolFocus
}
# V9 unified skill management; embedded to keep Windows launcher standalone.
function Invoke-SkillManagerV9([string]$Mode, [string]$Skill = '', [switch]$Approved, [switch]$Strict) {
    $path=Join-Path $ProjectDir 'data\local\zarzysseus_skill_manager_v9.py'
    $directory=Split-Path $path -Parent
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $source=@'
#!/usr/bin/env python3
"""Zarzysseus V9 read-only skill audit and narrowly scoped MCP consent store.

Does not execute skills, access the network, import third-party runners, or probe MCP servers.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def md_frontmatter(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not match:
        return {}, text
    try:
        from services.memory.skill_format import parse_frontmatter
        data, body = parse_frontmatter(text)
        return data if isinstance(data, dict) else {}, body
    except Exception:
        try:
            import yaml
            data = yaml.safe_load(match.group(1)) or {}
            return data if isinstance(data, dict) else {}, text[match.end():]
        except Exception:
            return {}, text[match.end():]


def declarations(fm):
    for key in ("mcpServers", "mcpservers", "mcp_servers", "mcp-servers"):
        if key in fm:
            value = fm[key]
            break
    else:
        return []
    if isinstance(value, dict):
        return [(str(k), v) for k, v in value.items() if isinstance(v, dict)]
    if isinstance(value, list):
        return [(str(v.get("name") or v.get("id") or f"server-{i+1}"),
                 {k: item for k, item in v.items() if k not in ("name", "id")})
                for i, v in enumerate(value) if isinstance(v, dict)]
    return []


def slug(value):
    return re.sub(r"[^A-Za-z0-9_]+", "_", value.strip()).strip("_").lower()[:36] or "server"


def digest(spec):
    return hashlib.sha256(json.dumps(spec, sort_keys=True, default=str, separators=(",", ":")).encode()).hexdigest()


def load_approvals(project):
    path = project / "data/local/zarzysseus-skill-v9-approvals.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("version") == 1 and isinstance(data.get("approved"), dict):
            return path, data["approved"]
    except (ValueError, OSError):
        pass
    return path, {}


def installed_servers(project):
    try:
        from core.database import SessionLocal, McpServer
        with SessionLocal() as db:
            return {x.id: {"enabled": bool(x.is_enabled), "transport": x.transport}
                    for x in db.query(McpServer).filter(McpServer.id.like("skill_%")).all()}
    except Exception:
        return None


def expected_names(fm):
    raw = fm.get("requires_toolsets") or []
    if isinstance(raw, str):
        return [x.strip().strip('"\'') for x in re.split(r"[,\s]+", raw.strip("[]")) if x.strip()]
    if isinstance(raw, list):
        return [str(x) for x in raw]
    return []


def requirements_status(skill_dir):
    findings = []
    req = skill_dir / "requirements.txt"
    if req.is_file():
        try:
            from importlib import metadata
            missing = []
            for line in req.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith(("-", ".", "git+", "http:", "https:")):
                    findings.append("Python requirement uses a non-index/option spec: needs manual verification")
                    continue
                name = re.match(r"([\w.-]+)", line)
                if name:
                    try:
                        metadata.version(name.group(1))
                    except metadata.PackageNotFoundError:
                        missing.append(name.group(1))
            if missing:
                findings.append("missing Python distributions: " + ", ".join(sorted(set(missing))))
        except Exception:
            findings.append("Python requirements not verified")
    if (skill_dir / "package.json").is_file() and not (skill_dir / "node_modules").is_dir():
        findings.append("npm package manifest present but node_modules missing")
    for name in ("run.py", "run.sh", "run.ps1", "runner.py", "runner.sh"):
        if (skill_dir / name).is_file():
            break
    return findings


def visible_server(spec):
    transport = str(spec.get("transport") or ("http" if spec.get("url") else "stdio")).lower()
    if transport in ("http", "sse", "streamable-http", "streamable_http"):
        target = urlparse(str(spec.get("url") or ""))
        return f"remote {transport}: {target.scheme}://{target.netloc or 'unconfigured'} (credentials hidden)"
    command = spec.get("command") or "unspecified"
    if isinstance(command, list):
        command = command[0] if command else "unspecified"
    return f"local stdio executable: {Path(str(command)).name} (arguments and credentials hidden)"


def audit(project, only=None):
    root = project / "data/skills/imported"
    path, approvals = load_approvals(project)
    rows = installed_servers(project)
    collected = []
    for md in sorted(root.glob("*/SKILL.md")):
        if only and md.parent.name != only:
            continue
        fm, body = md_frontmatter(md)
        skill_name = str(fm.get("name") or md.parent.name)
        native = expected_names(fm)
        runnable = any((md.parent / n).exists() for n in ("run.py", "run.sh", "run.ps1", "runner.py", "runner.sh", "scripts", "bin", "tools"))
        issues = requirements_status(md.parent)
        if runnable and not ("bash" in native or "python" in native):
            issues.append("executable skill has no declared native bash/python toolset")
        servers = []
        for name, spec in declarations(fm):
            key = f"{md.parent.name}/{name}"
            server_id = ("skill_" + slug(skill_name) + "_" + slug(name))[:90]
            current = (rows or {}).get(server_id)
            approved = approvals.get(key) == digest(spec)
            state = "enabled-config" if current and current["enabled"] else ("disabled-config" if current else "unregistered")
            if current and current["enabled"] and not approved:
                state = "legacy-enabled-config"
            if not approved and state not in ("legacy-enabled-config",):
                issues.append(f"{name}: explicit MCP approval required")
            if state in ("unregistered", "disabled-config"):
                issues.append(f"{name}: {state}")
            qualified_prefix = f"mcp__{server_id}__"
            if state in ("enabled-config", "legacy-enabled-config") and not any(x.startswith(qualified_prefix) for x in native):
                issues.append(f"{name}: no discovered MCP tools bound to requires_toolsets")
            servers.append({"name": name, "key": key, "spec": spec, "approved": approved,
                            "state": state, "server_id": server_id})
        if not fm:
            issues.append("frontmatter missing or cannot parse")
        collected.append({"folder": md.parent.name, "name": skill_name, "runnable": runnable,
                          "native": native, "servers": servers, "issues": issues})
    return collected, rows is not None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["doctor", "plan", "approve", "test"])
    parser.add_argument("--project", required=True)
    parser.add_argument("--skill", help="Folder name in data/skills/imported; omit for all")
    parser.add_argument("--yes", action="store_true", help="Explicit approval from host TUI/CLI")
    parser.add_argument("--strict", action="store_true", help="Return failure when readiness issues remain")
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    sys.path.insert(0, str(project))
    os.chdir(project) if project.is_dir() else None
    found, db_ok = audit(project, args.skill)
    if args.skill and not found:
        print(f"ERROR: imported skill not found: {args.skill}", file=sys.stderr)
        return 2
    if args.action == "test":
        print("PASS: V9 skill manager imports and runs; no MCP server launched")
        return 0
    if args.action == "approve":
        if not args.yes:
            print("ERROR: explicit approval required (--yes after reviewing plan)", file=sys.stderr)
            return 2
        path, approvals = load_approvals(project)
        changed = 0
        for skill in found:
            for server in skill["servers"]:
                # Approve exact declaration digest only; secrets are not logged.
                fingerprint = digest(server["spec"])
                if approvals.get(server["key"]) != fingerprint:
                    approvals[server["key"]] = fingerprint
                    changed += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            old_state = json.loads(path.read_text(encoding="utf-8"))
            legacy = old_state.get("legacy", {}) if isinstance(old_state, dict) else {}
        except (OSError, ValueError):
            legacy = {}
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"version": 1, "approved": approvals, "legacy": legacy}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(path)
        print(f"V9 approved {changed} changed MCP declaration(s); approval file restricted to current user")
        return 0
    print(f"Zarzysseus V9 {'SKILL INSTALL PLAN' if args.action == 'plan' else 'AGENT SKILLS HEALTH'}")
    print(f"Imported skills: {len(found)} | DB inspection: {'available' if db_ok else 'unavailable'}")
    unresolved = 0
    for skill in found:
        print(f"\n[{skill['folder']}] {skill['name']}")
        print("  Toolsets:", ", ".join(skill["native"]) if skill["native"] else "none declared")
        if not skill["servers"]:
            print("  MCP: none declared; native/skill runner route only")
        for server in skill["servers"]:
            print(f"  MCP {server['name']}: {visible_server(server['spec'])}")
            print(f"    registration={server['state']} exact-declaration-approved={'yes' if server['approved'] else 'no'}")
        if skill["issues"]:
            unresolved += 1
            for issue in skill["issues"]:
                print(f"  [attention] {issue}")
        else:
            print("  [configured] declared dependencies/tool routing appear ready; LIVE model execution NOT tested")
    print(f"\nSkills needing attention: {unresolved}. This report does not execute skill code or prove live model execution.")
    return 1 if args.strict and unresolved else 0


if __name__ == "__main__":
    raise SystemExit(main())
'@
    [System.IO.File]::WriteAllText($path, $source + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $python=Get-VenvPython
    if(-not (Test-Path -LiteralPath $python)) { $python='python' }
    $params=@($path,$Mode,'--project',$ProjectDir)
    if($Skill){$params+=@('--skill',$Skill)}
    if($Approved){$params+='--yes'}
    if($Strict){$params+='--strict'}
    & $python @params
    if($LASTEXITCODE -ne 0){throw "V9 skill manager $Mode failed (exit $LASTEXITCODE)"}
}
function Setup-SkillsV9([string]$Skill = '') {
    Invoke-SkillManagerV9 -Mode 'plan' -Skill $Skill
    Write-Host 'Dependencies and MCP servers may execute third-party code and make network connections.' -ForegroundColor Yellow
    $answer=Read-Host 'Type YES to approve the declarations and install/repair prerequisites'
    if($answer -cne 'YES'){Warn 'Setup cancelled; existing skills unchanged.';return}
    Invoke-SkillManagerV9 -Mode 'approve' -Skill $Skill -Approved
    if($Skill){
        $folder=Join-Path (Join-Path $ProjectDir 'data\skills\imported') $Skill
        if(-not (Test-Path -LiteralPath (Join-Path $folder 'SKILL.md'))){throw "Unknown skill: $Skill"}
        [void](Fix-Skill $folder)
    }else{
        foreach($folder in (Skill-Roots | Sort-Object FullName -Unique)){
            [void](Fix-Skill $folder.FullName)
        }
    }
    Repair-SkillRuntimeMetadata
    Invoke-SkillManagerV9 -Mode 'doctor' -Skill $Skill -Strict
    Write-Host 'Skill setup completed; live model tool calls still require host-side verification.'
}

# V10 Skill-Aware Model Advisor: embedded, standard-library-only Python helper.
function Invoke-ModelAdvisorV10([string]$Mode, [string]$Skill = '', [string]$Model = '') {
    $path=Join-Path $ProjectDir 'data\local\zarzysseus_model_advisor_v10.py'
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    $source=@'
#!/usr/bin/env python3
"""Zarzysseus V10 skill-aware model advisor. Python 3.11+, standard library.

Offline catalog + read-only hardware/installed-model discovery. Download and
per-skill preference changes are explicit. The non-mutating tool probe never
executes proposed tools. No Odysseus chat/model settings are altered.
"""
from __future__ import annotations
import argparse
import ctypes
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Catalog sizes are approximate Ollama Q4 download sizes in decimal GB, NOT
# peak RAM or tested Odysseus compatibility guarantees.
CATALOG = [
    dict(id='qwen3-vl:2b', gb=1.9, caps=['vision','tools'], quality=2, note='Small vision + tool calling'),
    dict(id='qwen3-vl:4b', gb=3.3, caps=['vision','tools'], quality=3, note='Mid-size visual agent'),
    dict(id='qwen3-vl:8b', gb=6.1, caps=['vision','tools'], quality=5, note='Browser screenshots verified in project testing with V8'),
    dict(id='qwen3-vl:30b', gb=20.0, caps=['vision','tools'], quality=7, note='Larger visual agent; tool flow unverified'),
    dict(id='qwen2.5-coder:3b', gb=1.9, caps=['code','tools'], quality=2, note='Small coding assistant'),
    dict(id='qwen2.5-coder:7b', gb=4.7, caps=['code','tools'], quality=4, note='Coding + native tools'),
    dict(id='qwen2.5-coder:14b', gb=9.0, caps=['code','tools'], quality=6, note='Larger code model'),
    dict(id='qwen3-coder:30b', gb=19.0, caps=['code','tools'], quality=8, note='Long-context coding model'),
    dict(id='llama3.1:8b', gb=4.9, caps=['tools'], quality=4, note='General tool calls; browser success depends on runtime'),
]
BY_ID = {m['id']: m for m in CATALOG}


def safe_local_url():
    host = os.environ.get('OLLAMA_HOST', '127.0.0.1:11434').strip()
    host = host.replace('http://','').replace('https://','').rstrip('/')
    if not re.fullmatch(r'(127\.0\.0\.1|localhost|\[::1\]):\d{2,5}', host):
        return 'http://127.0.0.1:11434'
    return 'http://' + host


def api(method, endpoint, payload=None, timeout=3):
    raw = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(safe_local_url()+endpoint, raw,
        {'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read(2_000_000).decode('utf-8'))


def installed_inventory():
    try:
        obj = api('GET', '/api/tags')
        return {m.get('name',''): m for m in obj.get('models',[]) if m.get('name')}
    except (OSError, ValueError, urllib.error.URLError):
        return {}


def installed_match(model_id, inventory):
    if model_id in inventory: return model_id
    if model_id.endswith(':latest') and model_id[:-7] in inventory: return model_id[:-7]
    if model_id + ':latest' in inventory: return model_id+':latest'
    # qwen3-vl:8b may also be labeled qwen3-vl:latest; do not infer equality
    return None


def host_ram_gb():
    if sys.platform.startswith('linux'):
        try:
            raw = Path('/proc/meminfo').read_text()
            return int(re.search(r'^MemTotal:\s*(\d+)',raw,re.M).group(1)) / 1024**2
        except (OSError, AttributeError, ValueError): pass
    if sys.platform == 'win32':
        class Memory(ctypes.Structure):
            _fields_ = [('dwLength',ctypes.c_ulong),('dwMemoryLoad',ctypes.c_ulong),
                        ('ullTotalPhys',ctypes.c_ulonglong),('ullAvailPhys',ctypes.c_ulonglong),
                        ('ullTotalPageFile',ctypes.c_ulonglong),('ullAvailPageFile',ctypes.c_ulonglong),
                        ('ullTotalVirtual',ctypes.c_ulonglong),('ullAvailVirtual',ctypes.c_ulonglong),
                        ('ullAvailExtendedVirtual',ctypes.c_ulonglong)]
        try:
            mem=Memory(); mem.dwLength=ctypes.sizeof(Memory)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(mem)):
                return mem.ullTotalPhys/1e9
        except Exception: pass
    return None


def gpu_info():
    names=[]; vram=[]
    if shutil.which('nvidia-smi'):
        try:
            out=subprocess.run(['nvidia-smi','--query-gpu=name,memory.total','--format=csv,noheader,nounits'],
                               capture_output=True,text=True,timeout=3,check=True).stdout
            for row in out.splitlines():
                name,mem=row.rsplit(',',1); names.append(name.strip()); vram.append(float(mem.strip())/1024)
        except (OSError,ValueError,subprocess.CalledProcessError): pass
    if sys.platform.startswith('linux'):
        for p in Path('/sys/class/drm').glob('card*/device/mem_info_vram_total'):
            try:
                value=int(p.read_text().strip())/1e9
                if value > .1: vram.append(value); names.append('DRM GPU')
            except (ValueError,OSError): pass
    if sys.platform == 'win32' and not vram:
        try:
            cmd=['powershell','-NoProfile','-Command',
                 'Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM | ConvertTo-Json -Compress']
            out=subprocess.run(cmd,capture_output=True,text=True,timeout=5,check=True).stdout
            objs=json.loads(out or '[]'); objs=[objs] if isinstance(objs,dict) else objs
            for obj in objs:
                names.append(str(obj.get('Name') or 'GPU'))
                # WMI AdapterRAM often overflows above 4GiB: treat as unknown.
        except (OSError, ValueError, subprocess.CalledProcessError): pass
    return {'names':sorted(set(names)), 'vram_gb':max(vram) if vram else None}


def load_skill(project: Path, skill_name: str):
    if not re.fullmatch(r'[\w.-]{1,100}', skill_name or '') or skill_name in ('.','..'):
        raise ValueError('Skill name must be an installed folder name')
    path=project/'data'/'skills'/'imported'/skill_name/'SKILL.md'
    if not path.is_file():
        raise ValueError('Imported skill not found: '+skill_name)
    return path.read_text(encoding='utf-8',errors='replace')[:16000]


def determine_category(skill_text, explicit='auto'):
    if explicit != 'auto': return explicit
    text=skill_text.lower()
    # Strongest signals first; do not let a generic "image" text imply vision
    if re.search(r'browser_take_screenshot|playwright|screenshot|screen\s*captur|visual\s*(?:browser|agent)|computer\s*use',text): return 'vision'
    if re.search(r'generate[_ -]?image|stable diffusion|comfyui|text.to.image',text): return 'image_generation'
    if re.search(r'coding|code review|write code|refactor|git\b|javascript|typescript|development|python script|apply_patch|edit_file|run\.py',text): return 'coding'
    if re.search(r'transcription|speech.to.text|text.to.speech|audio\b|podcast',text): return 'audio'
    if re.search(r'pdf|ocr\b|analy[sz]e image|interpret photo|visual|image understanding',text): return 'vision'
    if re.search(r'research|search the web|web_search|web_fetch|browsing',text): return 'research'
    return 'general'


def needs(category):
    if category in ('vision','visual_docs'): return {'vision','tools'}
    if category=='coding': return {'code','tools'}
    if category in ('general','research','automation'): return {'tools'}
    return set()


def fit(model, ram, vram):
    # Conservative rough estimate: quant weights plus KV cache / runtime headroom.
    estimate = model['gb']*1.25 + 1.6
    if vram is not None and estimate <= vram*0.90:
        return 'gpu-fit', 3, estimate
    if ram is not None and estimate > ram*0.90:
        return 'unlikely', 0, estimate
    if ram is not None and estimate <= ram*0.75:
        return ('hybrid/CPU' if vram is not None else 'RAM-fit/GPU-unknown'), 2, estimate
    if ram is not None:
        return 'tight', 1, estimate
    return 'unknown', 1, estimate


def test_data(project):
    path=project/'data/local/zarzysseus-model-v10-tests.json'
    try:
        obj=json.loads(path.read_text(encoding='utf-8'))
        return obj if isinstance(obj,dict) else {}
    except (OSError, ValueError): return {}


def prefs_path(project): return project/'data/local/zarzysseus-model-v10-prefs.json'


def prefs(project):
    try: return json.loads(prefs_path(project).read_text(encoding='utf-8'))
    except (OSError,ValueError): return {}


def save_json(path, obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    tmp.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    try: os.chmod(tmp,0o600)
    except OSError: pass
    tmp.replace(path)


def candidates(category, inventory, ram, vram, tests, preferred=None):
    required=needs(category)
    if category in ('audio','image_generation'):
        return []  # separate runtime, not language model
    results=[]
    for m in CATALOG:
        if not required.issubset(set(m['caps'])): continue
        status, f, memory=fit(m,ram,vram)
        installed=installed_match(m['id'],inventory)
        tested=tests.get(m['id'],{})
        probed=tested.get('tool_probe') is True
        score=m['quality']*4 + (25 if f==3 else 10 if f==2 else -10 if f==1 else -35) + (36 if installed else 0) + (12 if probed else 0) - (m['gb']*.6)
        if status=='unlikely': score-=75
        if vram is None and m['gb'] > 7: score-=18  # avoid recommending very large CPU-only loads
        if category=='research' and 'vision' in m['caps']: score-=4
        if m['id']==preferred: score+=7
        results.append({**m,'installed':bool(installed),'installed_name':installed,
                        'fit':status,'estimated_gb':round(memory,1),'tool_test':'pass' if probed else ('fail' if tested.get('tool_probe') is False else 'not-tested'),
                        'score':score,'preferred':m['id']==preferred})
    return sorted(results,key=lambda x:(x['fit']=='unlikely', -x['score'] if x['fit']!='unlikely' else x['gb'],x['gb'],x['id']))


def safe_ollama_tool_test(model_id):
    # Model must be installed; does not dispatch any tool, visit sites or use files.
    schema={'type':'function','function':{'name':'diagnostic_ping','description':'A safe simulated ping; do not execute.',
            'parameters':{'type':'object','properties':{'value':{'type':'integer'}},'required':['value']}}}
    answer=api('POST','/api/chat',{'model':model_id,'stream':False,'messages':[
        {'role':'system','content':'Call diagnostic_ping with value=7. Use a structured tool call, not text.'},
        {'role':'user','content':'Call diagnostic_ping with value 7 now.'}], 'tools':[schema], 'options':{'num_predict':768}},timeout=90)
    calls=answer.get('message',{}).get('tool_calls',[])
    for c in calls:
        fn=c.get('function',{})
        arguments=fn.get('arguments',{})
        if isinstance(arguments,str):
            try: arguments=json.loads(arguments)
            except ValueError: arguments={}
        if fn.get('name')=='diagnostic_ping' and isinstance(arguments,dict) and arguments.get('value')==7:
            return True
    return False


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['recommend','json','best','test','install','pin','pins'])
    p.add_argument('--project',required=True)
    p.add_argument('--skill',default='')
    p.add_argument('--category',choices=['auto','vision','coding','general','research','automation','audio','image_generation'],default='auto')
    p.add_argument('--model',default='')
    p.add_argument('--yes',action='store_true')
    p.add_argument('--ram-gb',type=float,default=None,help='Override undetectable RAM (for tests)')
    p.add_argument('--vram-gb',type=float,default=None,help='Override undetectable GPU VRAM (for tests)')
    args=p.parse_args(argv)
    project=Path(args.project).expanduser().resolve()
    text=load_skill(project,args.skill) if args.skill else ''
    category=determine_category(text,args.category)
    inventory=installed_inventory()
    ram=args.ram_gb if args.ram_gb is not None else host_ram_gb()
    gpu=gpu_info()
    vram=args.vram_gb if args.vram_gb is not None else gpu['vram_gb']
    saved=prefs(project)
    preferred=saved.get(args.skill,'') if args.skill else ''
    ranked=candidates(category,inventory,ram,vram,test_data(project),preferred)
    if args.action in ('recommend','json','best'):
        doc={'skill':args.skill or 'general','category':category,'hardware':{'ram_gb':round(ram,1) if ram else None,
            'gpu_names':gpu['names'],'gpu_vram_gb':round(vram,1) if vram else None},
            'ollama_reachable':bool(inventory),'suggestions':ranked,'saved_preference':preferred}
        if args.action=='json': print(json.dumps(doc,indent=2));return 0
        if args.action=='best':
            if not ranked: return 3
            print(ranked[0]['id']);return 0
        print('=== ZARZYSSEUS V10 SKILL-AWARE MODEL ADVISOR ===')
        print(f"Skill: {doc['skill']} | Workload: {category}")
        print(f"RAM: {ram:.1f} GB" if ram else 'RAM: unknown', '| GPU:', ', '.join(gpu['names']) or 'undetected', '| dedicated VRAM:',f'{vram:.1f} GB' if vram else 'unknown')
        print(f'Installed Ollama models: {len(inventory)} (0 may mean Ollama offline)')
        if not ranked:
            print('No text/vision model can directly perform this workload; configure its specialized runtime/backend.');return 0
        for i,m in enumerate(ranked[:9],1):
            print(f" {i}. {m['id']:<24} {m['fit']:<20} {'INSTALLED' if m['installed'] else 'download'} | tool-test={m['tool_test']}")
            print(f"    ~{m['gb']} GB download, ~{m['estimated_gb']} GB estimated runtime; {m['note']}")
        if preferred: print('Saved skill preference:',preferred,'(not an automatic Odysseus model switch)')
        print('Memory figures are estimates, not guarantees. Published capability != proven Odysseus integration.')
        print('Nothing is downloaded or switched by this command.')
        return 0
    if args.action=='pins':
        print(json.dumps(saved,indent=2,sort_keys=True));return 0
    if args.action=='pin':
        if not args.skill or not args.model or args.model not in BY_ID:
            p.error('pin requires --skill INSTALLED_SKILL --model KNOWN_MODEL')
        if args.model not in [m['id'] for m in ranked]: p.error('model lacks mandatory workload capabilities')
        if not args.yes: p.error('pin requires explicit --yes')
        saved[args.skill]=args.model
        save_json(prefs_path(project),saved)
        print('Saved advisory preference; active Odysseus chat model unchanged.')
        return 0
    if args.action=='test':
        if not args.model: p.error('test requires --model')
        installed=installed_match(args.model,inventory)
        if not installed:
            print('ERROR: model is not installed or Ollama is unreachable.',file=sys.stderr);return 2
        try: passed=safe_ollama_tool_test(installed)
        except (OSError,ValueError,urllib.error.URLError) as exc:
            print('ERROR: Ollama tool probe could not complete:',exc,file=sys.stderr);return 2
        results=test_data(project)
        results[args.model]={'tool_probe':passed,'timestamp':int(time.time()),'scope':'Ollama synthetic tool schema only'}
        save_json(project/'data/local/zarzysseus-model-v10-tests.json',results)
        print(('PASS' if passed else 'FAIL')+': structured diagnostic_ping tool proposal'+('' if passed else ' missing')+'. Tool was NOT executed.')
        print('This does not prove MCP, screenshot rendering or agent chat continuity.')
        return 0 if passed else 1
    if args.action=='install':
        selected=args.model or (ranked[0]['id'] if ranked else '')
        if selected not in BY_ID or selected not in [m['id'] for m in ranked]:
            print('ERROR: select a supported model for this workload (no arbitrary pull).',file=sys.stderr);return 2
        row=next(m for m in ranked if m['id']==selected)
        print(f"Proposed Ollama download: {selected} (~{row['gb']} GB). No chat model will be changed.")
        if row['installed']:
            print('Already installed; nothing downloaded.');return 0
        if row['fit']=='unlikely':
            print('WARNING: estimated memory exceeds physical RAM. Refusing automatic selection.',file=sys.stderr);return 2
        if not args.yes:
            if not sys.stdin.isatty():
                print('ERROR: interactive approval required (or explicit --yes).',file=sys.stderr);return 3
            if input('Type YES to download this model: ').strip() != 'YES':
                print('Cancelled.');return 3
        executable=shutil.which('ollama')
        if not executable:
            print('ERROR: ollama executable not found. Install Ollama first.',file=sys.stderr);return 2
        return subprocess.run([executable,'pull',selected],check=False).returncode
    return 2

if __name__=='__main__':
    raise SystemExit(main())
'@
    [System.IO.File]::WriteAllText($path,$source + "`n",(New-Object System.Text.UTF8Encoding($false)))
    $python=Get-VenvPython
    if(-not (Test-Path -LiteralPath $python)) { $python='python' }
    $params=@($path,$Mode,'--project',$ProjectDir)
    if($Skill) { $params+=@('--skill',$Skill) }
    if($Model) { $params+=@('--model',$Model) }
    & $python @params
    if($LASTEXITCODE -ne 0) { throw "V10 model advisor $Mode exited $LASTEXITCODE" }
}
function Install-AdvisorModelV10([string]$Skill = '',[string]$Model = '') {
    Invoke-ModelAdvisorV10 -Mode 'recommend' -Skill $Skill
    Write-Host 'Model pull may download several GB. The current Odysseus chat model will NOT change.' -ForegroundColor Yellow
    $answer=Read-Host 'Type YES to approve downloading the suggested/selected model'
    if($answer -cne 'YES') { Warn 'Model installation cancelled.'; return }
    # A second process never uses a shell command constructed from model text.
    $path=Join-Path $ProjectDir 'data\local\zarzysseus_model_advisor_v10.py'
    $python=Get-VenvPython
    if(-not (Test-Path -LiteralPath $python)) { $python='python' }
    $params=@($path,'install','--project',$ProjectDir,'--yes')
    if($Skill) { $params+=@('--skill',$Skill) }
    if($Model) { $params+=@('--model',$Model) }
    & $python @params
    if($LASTEXITCODE -ne 0) { throw "V10 model installation failed ($LASTEXITCODE)" }
}
function Pin-AdvisorModelV10([string]$Skill,[string]$Model) {
    if(-not $Skill -or -not $Model) { Fail 'Use model-advisor-pin with an imported skill and catalog model.' }
    Invoke-ModelAdvisorV10 -Mode 'recommend' -Skill $Skill
    $confirm=Read-Host "Save $Model as recommendation for $Skill? Type YES"
    if($confirm -cne 'YES') { Warn 'Cancelled.'; return }
    $path=Join-Path $ProjectDir 'data\local\zarzysseus_model_advisor_v10.py'
    $python=Get-VenvPython
    if(-not (Test-Path -LiteralPath $python)) { $python='python' }
    & $python $path pin --project $ProjectDir --skill $Skill --model $Model --yes
    if($LASTEXITCODE -ne 0) { throw 'Could not save preference.' }
}

function Skills-Menu {
    while($true){
        Write-Host "`nSKILLS  [1] Fave Skills  [2] Fix All  [3] List  [4] Repair Tool Routing  [5] V9 Health  [6] V9 Setup  [7] V10 Model Advisor  [8] V10 Test Tool Call  [9] V10 Install Model  [0] Back"
        switch(Read-Host 'Choose'){
            '1'{Fave-Skills};'2'{Fix-All-Skills};'3'{Skill-Roots | Select-Object -ExpandProperty FullName | Sort-Object -Unique};'4'{Repair-SkillRuntimeMetadata;Install-QwenToolFocus};'5'{Invoke-SkillManagerV9 'doctor'};'6'{Setup-SkillsV9};'7'{$s=Read-Host 'Imported skill folder (blank for general)';Invoke-ModelAdvisorV10 -Mode 'recommend' -Skill $s};'8'{$m=Read-Host 'Installed Ollama model';if($m){Invoke-ModelAdvisorV10 -Mode 'test' -Model $m}};'9'{$s=Read-Host 'Imported skill folder (blank for general)';$m=Read-Host 'Catalog model ID (blank for top recommendation)';Install-AdvisorModelV10 -Skill $s -Model $m};'0'{return}
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
        Write-Host '14 Set/check default Agent workspace'
        Write-Host '15 Start ChromaDB / tool index'
        Write-Host '16 Sync Ollama native-tool endpoints'
        Write-Host '17 Tool-calling health'
        Write-Host '18 Install/upgrade Qwen explicit-tool + /skill focus (guarded patch)'
        Write-Host '19 Install/start Docker Desktop + ChromaDB (on demand)'
        Write-Host '20 MCP / FreeMCP'
        Write-Host '21 Repair/check same-chat continuity'
        Write-Host '22 Repair/check Cookbook reliability (no OS update)'
        Write-Host '23 Agent Doctor (read-only)'
        Write-Host '24 Agent Repair + browser reasoning-only recovery'
        Write-Host '25 Agent routing + recovery smoke test'
        Write-Host '26 Roll back latest agent reliability patch'
        Write-Host '27 Switch to Docker Desktop mode (requires full source)'
        Write-Host '28 Set native CPU-only / Full profile (advisory)'
        Write-Host '0  Exit'
        Write-Host 'Tip: star https://github.com/zarzorr69/zarzyssues if it helps you!' -ForegroundColor DarkCyan
        $choice=Read-Host 'Choose'
        try{
            switch($choice){
                '1'{Install-Stack};'2'{Start-App};'3'{Stop-App};'4'{Show-Status};
                '5'{Model-Browser};'6'{Start-Ollama};'7'{Skills-Menu};'8'{HF-Token};
                '9'{Show-Accelerator};'10'{Enable-Startup};'11'{Disable-Startup};
                '12'{Update-Repo};'13'{Network-Menu};'14'{Workspace-Default};
                '15'{Ensure-Chromadb -Force};'16'{Sync-Ollama};'17'{Tool-Health};
                '18'{Install-QwenToolFocus};'19'{if (Ensure-Docker -Force) { Ensure-Chromadb -Force }};'20'{Mcp-Menu};'21'{Install-ChatContinuityFix};'22'{Install-CookbookFixes};'23'{Agent-Doctor};'24'{Agent-Repair};'25'{Invoke-AgentReliability 'smoke';Invoke-AgentRuntimeV3 'smoke'};'26'{Agent-Rollback};'27'{ $null=ZZ-GetDockerKit; ZZ-Store $ZZModeFile 'docker'; Write-Host 'Docker mode saved. Reopen the TUI to enter Docker mode.'; return };'28'{ $desired=Read-Host 'Type cpu or full'; if($desired -in @('cpu','full')) { ZZ-Store (Join-Path $ZZModeDir 'hardware-native.txt') $desired; Write-Host 'Saved. CPU-only native is advisory until backend GPU selection is configured.' } };'0'{return};default{Warn 'Unknown choice.'}
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
        'ollama-pull'{Pull-Ollama $Argument};'hf-pull'{Download-Hub $Argument};'model-install'{Install-Model $Argument};
        'ollama-sync'{Sync-Ollama};'models'{Model-Browser};'skills'{Skills-Menu};
        'skills-doctor'{Invoke-SkillManagerV9 -Mode 'doctor' -Skill $Argument};'skills-setup'{Setup-SkillsV9 -Skill $Argument};
        'model-advisor'{Invoke-ModelAdvisorV10 -Mode 'recommend' -Skill $Argument};'model-advisor-json'{Invoke-ModelAdvisorV10 -Mode 'json' -Skill $Argument};
        'model-advisor-test'{Invoke-ModelAdvisorV10 -Mode 'test' -Model $Argument};
        'model-advisor-install'{if($Argument -match '^[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.-]+$'){Install-AdvisorModelV10 -Model $Argument}else{Install-AdvisorModelV10 -Skill $Argument}};
        'model-advisor-pin'{if($Argument -notmatch '^([^=]+)=(.+)$'){Fail 'Use model-advisor-pin skill=model'};Pin-AdvisorModelV10 -Skill $Matches[1] -Model $Matches[2]};
        'model-advisor-pins'{Invoke-ModelAdvisorV10 -Mode 'pins'};
        'skills-fix-all'{Fix-All-Skills};'skills-runtime-fix'{Repair-SkillRuntimeMetadata;Install-QwenToolFocus};'skills-mcp-fix'{Provision-SkillMcpServers};'tool-json-fix'{Install-DirectToolJsonRecovery};'accelerator-status'{Show-Accelerator};
        'workspace-default'{if($Argument -eq 'status'){Workspace-Default -Status}else{Workspace-Default}};
        'chromadb-start'{Ensure-Chromadb -Force};'docker-setup'{if (Ensure-Docker -Force) { Ensure-Chromadb -Force }};'tool-health'{Tool-Health};
        'mcp-setup'{Setup-Mcp};'mcp-health'{Show-McpHealth};'freemcp-setup'{Ensure-FreeMcp};'freemcp-status'{FreeMcp-Status};'freemcp-search'{FreeMcp-Search $Argument};'freemcp-login'{FreeMcp-Login};
        'agent-tool-focus-install'{Install-QwenToolFocus};
        'agent-doctor'{Agent-Doctor};'agent-repair'{Agent-Repair};'agent-smoke'{Invoke-AgentReliability 'smoke';Invoke-AgentRuntimeV3 'smoke'};'agent-rollback'{Agent-Rollback};
        'chat-continuity-fix'{if($Argument -eq 'status'){Install-ChatContinuityFix -Status}else{Install-ChatContinuityFix;if(Current-Process){Stop-App;Start-App}}};
        'cookbook-fix'{if($Argument -eq 'status'){Install-CookbookFixes -Status}elseif($Argument -eq 'rollback-oneclick'){Invoke-CookbookOneClickV10_1 -Mode 'rollback';if(Current-Process){Stop-App;Start-App}}elseif($Argument -eq 'progress'){Invoke-CookbookProgressV10_2 -Mode 'install';if(Current-Process){Stop-App;Start-App}}elseif($Argument -eq 'rollback-progress'){Invoke-CookbookProgressV10_2 -Mode 'rollback';if(Current-Process){Stop-App;Start-App}}elseif($Argument -eq 'autoadd'){Invoke-CookbookAutoAddV11_6 -Mode 'install';if(Current-Process){Stop-App;Start-App}}elseif($Argument -eq 'rollback-autoadd'){Invoke-CookbookAutoAddV11_6 -Mode 'rollback';if(Current-Process){Stop-App;Start-App}}elseif(-not $Argument){Install-CookbookFixes;if(Current-Process){Stop-App;Start-App}}else{Fail 'Usage: cookbook-fix [status|progress|rollback-progress|rollback-oneclick|autoadd|rollback-autoadd]'}};
        'network-mode'{if ($Argument -eq 'status' -or -not $Argument) { Show-Network } else { Set-Network $Argument }};
        default{Fail "Unknown command: $Action"}
    }
}catch{Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
