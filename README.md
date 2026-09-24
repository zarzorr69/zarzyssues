# Zarzysseus

An interactive AI installation and service-management toolkit for **Odysseus native Linux and Windows installs**, with my own custom favorite models and skills available for install under `Fave` selections.

Zarzysseus is a separate installer and management TUI for the upstream [Odysseus project](https://github.com/odysseus-dev/odysseus). It helps discover an existing checkout, install the native application, browse models, install skills, and repair supported dependencies. **The Linux and Windows editions do not yet have identical feature coverage**; see [Windows support](#windows-support) below.

## Recommended first-time setup: Hugging Face (Linux **and** Windows)

**Hugging Face sign-in is recommended for either installer**, especially when downloading gated or private models. Public models often work without a token. A token alone does not grant gated-model access: open the model page and accept its terms or request access if required.

1. Create or sign in to your account at [huggingface.co](https://huggingface.co/).
2. Open **[Settings → Access Tokens](https://huggingface.co/settings/tokens)** and create a **Read** token, or a fine-grained token with read access to the specific repositories you want. Do not use a write token just for model downloads.
3. Copy the token privately. **Do not paste it into GitHub, your README, screenshots, chat, or a shared shell command.**
4. **Linux:** launch `./zarzysseus.sh`, open **Hugging Face / Model Files → Set / Inspect / Clear HF Token**, and paste the token when prompted (input is hidden). Or use `./zarzysseus.sh hf-token` after native stack installation; check it with `./zarzysseus.sh hf-token status`.
5. **Windows:** launch `zarzysseus.ps1`, choose **Hugging Face setup (recommended)**, and paste the token at the hidden prompt. Check it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 hf-token-status`.

Windows stores the Zarzysseus token encrypted for the current Windows user. On Linux, the installer persists the token in the Odysseus configuration with restrictive file permissions; keep your machine and configuration files private. You can clear a Zarzysseus-managed token in either TUI. Other Hugging Face tools may store separate credentials.

## Linux installation

Run this in a Linux terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/zarzorr69/zarzyssues/main/zarzysseus.sh -o zarzysseus.sh && chmod +x zarzysseus.sh && ./zarzysseus.sh
```

The script is downloaded before execution so its interactive TUI retains terminal input. The URL assumes the public repository's default branch is `main` and `zarzysseus.sh` is at its root.

### Linux distribution support

Zarzysseus detects the Linux distribution and chooses an available package manager. The **package-manager adapters** in the current Linux installer cover these distribution families and examples:

| Distribution family | Examples | Detected package manager |
| --- | --- | --- |
| Arch Linux | Arch, CachyOS, Manjaro, EndeavourOS, Garuda | `pacman` |
| Debian / Ubuntu | Debian, Ubuntu, Linux Mint, Pop!_OS, Kali, MX Linux | `apt-get` |
| Fedora / RHEL | Fedora, RHEL, CentOS-family, Rocky Linux, AlmaLinux, Nobara, Amazon Linux, Oracle Linux | `dnf5`, `dnf`, `microdnf`, or `yum` |
| openSUSE / SUSE | openSUSE and SUSE derivatives | `zypper` |
| Alpine | Alpine Linux | `apk` |
| Void | Void Linux | `xbps-install` |
| Gentoo | Gentoo and Funtoo | `emerge` |
| Solus | Solus | `eopkg` |
| Clear Linux | Clear Linux | `swupd` |
| Mageia / related RPM distributions | Mageia and compatible systems | `urpmi` |
| Photon OS | VMware Photon OS | `tdnf` |
| Slackware | Slackware | `slackpkg` |
| NixOS | NixOS | `nix` |
| GNU Guix | Guix System | `guix` |
| rpm-ostree systems | Fedora Atomic desktops and compatible systems | `rpm-ostree` |

**What “supported” means here:** the Linux installer has package-manager detection and adapters for these ecosystems; this does **not** mean every model, accelerator, service-management operation, or distribution release has been tested. It detects `systemd`, OpenRC, runit, and s6, but some managed-service features are systemd-specific. Immutable systems and layered packages may require a reboot. GPU drivers, Python/runtime compatibility, repository availability, and model requirements can impose further limitations.

### Linux features

- Terminal-size-aware installation and service-management TUI
- Existing Odysseus checkout discovery and launch-time upstream Git check
- AMD/ROCm, NVIDIA/CUDA, Intel/XPU and CPU detection and supported repair paths
- Normal, L.P.S. (Low Power Spec), and Desert Ant Labs model groups
- Text, photo, video, and audio browsers; auto-fit modes; manual batch selection
- Favorite model and skill options
- Skill health checks and selected-skill / Fix All dependency repair
- Provider login handoff where supported

## Windows installation

Use **Windows PowerShell 5.1 or later** on Windows 10/11. Paste the following into PowerShell; the script downloads to a file before execution, preserving keyboard input for its menu:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zarzorr69/zarzyssues/main/zarzysseus.ps1' -OutFile "$env:TEMP\zarzysseus.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\zarzysseus.ps1"
```

Alternatively, download `zarzysseus.ps1` from the repository and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1
```

The PowerShell script checks for an existing Odysseus checkout before opening its menu. **It does not upgrade Windows merely because you opened the TUI or browsed models.** Installing the app or confirming model downloads may install relevant prerequisites using WinGet. The `-ExecutionPolicy Bypass` argument applies only to the launched process; it does not change your permanent execution policy.

### Windows support

| Capability | Native Windows edition |
| --- | --- |
| Install/update Odysseus | Yes: upstream checkout, isolated Python environment, dependencies, setup |
| Run/stop/status | Yes: local Python server with current-user startup option |
| Local chat models | Ollama install/start/pull and manual text catalog |
| Photo/video/audio catalog | Browse and download curated Hugging Face snapshots; **inference runtime is separate** |
| Manual selection | Choose and confirm before any model installation; Tab switches model families, 1–5 filter types |
| Hugging Face token | Hidden entry, encrypted at rest for current Windows user |
| Favorite skills | Local starter templates and Python prerequisites; app import/registration may need manual setup |
| Skill fixer | Declared `requirements.txt` / `package.json` dependencies; not a guarantee for undocumented requirements |
| Hardware | Adapter display; Ollama is the practical native local-model path |
| vLLM / SGLang / ROCm | **Not native Windows installation targets**; use Linux or WSL2 where supported |
| Desert Ant Labs | Windows SDK exists, but no Windows CLI installer is bundled here |

Native Windows Odysseus uses **Python 3.11+**; Git for Windows supplies Bash for some upstream Cookbook tasks. WinGet helps install Git, Python, Ollama and supported prerequisites. Windows antivirus, driver versions, permissions and individual upstream features may require manual intervention. **This companion has not been validated end-to-end on a Windows host; treat it as an initial Windows edition, not a feature-identical port of the Linux script.**

## Requirements

- Linux with a supported package manager **or** Windows 10/11 with PowerShell 5.1+ and preferably WinGet
- Internet connection for initial source, dependency and model downloads
- Disk, RAM and (where needed) GPU resources appropriate for selected models
- Appropriate permissions for package installation; third-party accounts require their own authorization

Review the installer's fit, size, and health readouts before choosing large models. Parameter counts and resource estimates are planning information, not measured guarantees.

## Upstream

[odysseus-dev/odysseus](https://github.com/odysseus-dev/odysseus)

Zarzysseus is an independently maintained installer and management toolkit built around Odysseus. For the upstream native Windows setup instructions, see [Odysseus's setup guide](https://github.com/odysseus-dev/odysseus/blob/dev/website/setup.md).

**Enjoying Zarzysseus? 
A ⭐ on [the project](https://github.com/zarzorr69/zarzyssues) would mean a lot — thank you for supporting it!**
