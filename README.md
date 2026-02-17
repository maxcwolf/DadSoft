# DadSoft

A one-click toolkit for setting up your dad's Mac. Built for Apple Silicon.

**Two features, zero confusion:**

- **Windows 11 Installer** -- Downloads and sets up Windows 11 in a virtual machine (UTM), completely automated. Dad gets a "Open Windows 11" button when it's done.
- **Remote Control Setup** -- Installs and configures AnyDesk so your dad can let you remote into his Mac with one click. Dad gets a "Let [Your Name] Take Over My Computer" button.

The app walks through everything step by step, installs all prerequisites automatically, and leaves big friendly buttons on the home screen for daily use.

---

## Download & Install

1. Go to the [**Releases page**](../../releases/latest)
2. Download **DadSoft-Installer.dmg**
3. Open the DMG and drag **DadSoft** into your **Applications** folder
4. **First launch only:** Right-click DadSoft in Applications and click **Open**, then click **Open** again on the dialog that appears (this is a one-time macOS security step for apps downloaded from the internet)

After that first time, DadSoft opens normally with a double-click.

---

## What It Does

### Windows 11 on Mac
DadSoft handles the entire setup:
- Checks your Mac is compatible
- Installs Xcode Command Line Tools, Homebrew, UTM, and QEMU
- Downloads Windows 11 ARM directly from Microsoft
- Creates and configures the virtual machine
- Walks you through the Windows installation with numbered steps

When it's done, a purple **"Open Windows 11"** button appears on the home screen.

### Remote Control (AnyDesk)
DadSoft sets up remote access so your son can help:
- Installs AnyDesk via Homebrew
- Walks through granting Screen Recording and Accessibility permissions
- Guides you through setting an unattended access password
- Shows your AnyDesk address with a one-tap send to your son via Messages

When it's done, a blue **"Let [Son] Take Over My Computer"** button appears on the home screen -- one click opens AnyDesk and messages your son the address.

### First Launch
On first launch, DadSoft asks "Who is your son?" and lets you pick from your contacts. This way, sharing your remote access info is a single button press -- no typing, no menus.

---

## Requirements

- Apple Silicon Mac (M1 / M2 / M3 / M4)
- macOS 13 Ventura or later
- ~30 GB free disk space (for Windows VM)
- Internet connection

---

## Uninstall

DadSoft includes a built-in uninstaller. Click **Uninstall...** on the home screen to selectively remove the Windows VM, downloaded files, UTM, QEMU, and all related data.

---

## Building from Source

```bash
cd DadSoft
bash build.sh
# Output: ../DadSoft.app
```

Requires Xcode Command Line Tools and Swift 5.9+.
