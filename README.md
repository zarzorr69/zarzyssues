# Zarzysseus

An interactive AI installation and service-management toolkit for Odysseus native Linux installs with my own custom favorite models and skills available for install under `Fave` selections.

Zarzysseus is a Linux installer and management TUI for the upstream [Odysseus project](https://github.com/odysseus-dev/odysseus). It helps detect the local hardware, install models and skills, resolve supported dependencies, and manage a native Odysseus installation.

## Install

Run this in a Linux terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/zarzorr69/zarzyssues/main/zarzysseus.sh -o zarzysseus.sh && chmod +x zarzysseus.sh && ./zarzysseus.sh
```

The script is downloaded before execution so its interactive TUI retains access to terminal input. The URL assumes the public repository's default branch is `main` and `zarzysseus.sh` is at its root.

## Linux distribution support

Zarzysseus detects the Linux distribution and chooses an available package manager. The **package-manager adapters** in the current installer cover these distribution families and examples:

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

**What “supported” means here:** the installer contains package-manager detection and installation/update adapters for these ecosystems. This is **not** a claim that every model, accelerator backend, service-management operation, or distribution release has been tested or works identically on every one. The script also detects `systemd`, OpenRC, runit, and s6, but some managed-service features are systemd-specific. Immutable/declarative systems may require extra setup or a reboot; `rpm-ostree` explicitly requests a reboot after layering new dependencies. Hardware, repository availability, Python/runtime compatibility, and selected models can impose additional limitations.

## Features

- Interactive, terminal-size-aware installer and service manager
- Upstream Odysseus checkout discovery and launch-time Git update check
- Accelerator detection and supported dependency-repair workflows
- Text, photo, video, and audio model browsing and installation
- Normal, L.P.S. (Low Power Spec), and Desert Ant Labs model groups
- Hardware-aware auto-fit options and manual batch model selection
- Skill installation, health checks, and selected-skill / Fix All dependency repair
- Provider login handoff when a third-party service requires authorization

## Requirements

A Linux system with a supported package manager, an internet connection for downloads, and suitable hardware for the models you choose. Some operations need `sudo`; some external services require your own account authorization. Consult the installer's hardware-fit and health readouts before choosing large models.

## Upstream

[odysseus-dev/odysseus](https://github.com/odysseus-dev/odysseus)

Zarzysseus is a separate installer and management toolkit built around Odysseus.
