
<div align="center">

# 🛠️ shtools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue)](https://github.com)
[![Status](https://img.shields.io/badge/Status-Active-green)](#)

A collection of personal utility scripts for media processing and file management — always at hand on any machine.

![Made with VHS](docs/demo.gif)

</div>

---

## ⚡ Quick Start

Add this alias to your `.bashrc` or `.zshrc`:

```bash
alias tools='curl -Ls https://raw.githubusercontent.com/thegabriele97/shtools/main/launcher.sh | bash -s --'
```

Then run:

```bash
tools
```

This opens an interactive TUI where you can browse all available scripts, read their description, usage, and examples — and run them directly.

> **Optional:** `fzf` enables a modern, fast interactive interface. If not available, the script automatically falls back to a minimal menu-based interface.

---

## 📖 Usage

**Interactive mode** — browse and run scripts via TUI:
```bash
tools
```

**Direct mode** — run a script directly with arguments:
```bash
tools <command> [args...]
```

---

## 📦 Available Scripts

### Media Compression

| Command | Description | Dependencies |
|---------|-------------|---|
| `compress-images` | Compress images to WebP preserving folder structure | `cwebp`, `parallel` |
| `compress-video` | Compress video files in a folder while preserving all metadata | `ffmpeg` |
| `compress-video-sample-compare` | Generate compressed clips at different CRF values for visual comparison | `ffmpeg` |

### Media Processing

| Command | Description | Dependencies |
|---------|-------------|---|
| `concat-clips` | Inspect, normalize and concatenate video clips into a single file | `ffmpeg`, `ffprobe` |
| `copy-exif` | Copy EXIF metadata (dates, GPS, camera info) from originals to converted images | `exiftool` |

### File Management

| Command | Description | Dependencies |
|---------|-------------|---|
| `find-hardlinks` | Search for files in a path and check if they have a hard link in a second path (inode-based) | `find`, `ls` |
| `nextcloud-upload` | Upload a file or folder to a Nextcloud public share via WebDAV | `curl` |

## Adding a new script

1. Create your script in `scripts/` with the standard header:

```bash
#!/bin/bash
# @description Short description shown in the TUI
# @usage command-name <required_arg> [optional_arg]
# @example command-name /some/path value
# @deps comma, separated, dependencies
```

2. Register it in `tools.sh`:

```bash
SCRIPTS=(
  ...
  "your-script.sh|your-command"
)
```

3. Push to GitHub — it's immediately available on all machines.

## Local development

Clone the repo and run `tools` from inside it — it will automatically prefer local files in `./scripts/` over the remote ones, so you can test changes without pushing first.

```bash
git clone https://github.com/thegabriele97/shtools
cd shtools
bash tools.sh
```

## How it works

`tools.sh` is the single entry point. When invoked:
- with no arguments, it opens the fzf TUI
- with arguments, it runs the matching script directly
- with `--preview <name>`, it prints script metadata (used internally by fzf)

Scripts are fetched from GitHub at runtime and executed in memory — nothing is written to disk permanently. When running from inside the cloned repo, local files take priority over remote ones.