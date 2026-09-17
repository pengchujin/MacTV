<p align="center"><a href="README.md">简体中文</a> · <strong>English</strong></p>

<div align="center">
  <img src="docs/images/app-icon.svg" width="108" alt="MacTV icon">
  <h1>MacTV · TV Remote</h1>
  <p>Make your TV feel more at home with your Mac.</p>
  <p>Control your TV from your Mac, and your Mac with your TV remote. Connected over HDMI-CEC, with no Wi-Fi required.</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Apple_Silicon-arm64-111111?style=flat-square" alt="Apple Silicon">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-111111?style=flat-square" alt="MIT License"></a>
  </p>
  <p><a href="https://github.com/pengchujin/MacTV/releases/download/v0.1.2/MacTV-v0.1.2-macOS-arm64.dmg"><img src="docs/images/download-en.svg" width="196" height="44" alt="Download MacTV"></a></p>
  <p><a href="docs/COMPATIBILITY.md">Compatibility (Chinese)</a> · <a href="https://github.com/pengchujin/MacTV/issues">Report an issue</a></p>
  <br>
  <img src="docs/images/mactv-live.png" width="640" alt="MacTV connected to a REDMI display with the input selection menu open">
  <p><sub>MacTV running with a MiTV-MFFU1 display. Screenshots show the Chinese interface; English is also supported.</sub></p>
</div>

## Control your TV and Mac, both ways

MacTV is a Mac menu bar app that lets you adjust TV volume with your familiar keyboard controls and access TV power, menus, and inputs from the menu bar. Your TV remote can also control playback, switch tracks and apps, and move and click the mouse on your Mac. Available features depend on your TV and Mac.

- **Keyboard volume keys** — Use your Mac’s volume and mute keys when audio is routed through HDMI.
- **Control your Mac with a TV remote** — Switch tracks and apps or play/pause in media mode. Mouse mode adds accelerated movement, six speed levels, and hold-and-release OK to right-click. Back maps to Esc. Enable it in Settings; available keys depend on your TV.
- **Menu bar remote** — Navigate, confirm, and go back, with wake, standby, and menu commands where supported by your TV.
- **Input selection** — Request a switch back to this Mac or to another HDMI input. Results depend on the TV.
- **Native experience** — Light and dark appearance, VoiceOver, and Simplified Chinese, Traditional Chinese, and English support.

Open the downloaded DMG and drag MacTV into Applications to install.

## Install with Homebrew

```sh
brew install --cask pengchujin/tap/mactv
```

Open MacTV from Applications. To update:

```sh
brew update
brew upgrade --cask pengchujin/tap/mactv
```

## Get started in three steps

**1 · Connect your TV**

Connect your TV through a CEC-capable HDMI port or adapter, and enable HDMI-CEC in the TV’s settings. Depending on the brand, it may be called SIMPLINK, Anynet+, or BRAVIA Sync.

**2 · Open the remote**

Launch the app and click the remote icon in the menu bar. Use the arrow keys to navigate, Return to confirm, and Delete to go back. The input menu includes options to switch back to this Mac and request HDMI 1–4.

**3 · Enable keyboard volume control**

Open the app’s settings, enable control with your Mac’s volume keys, and allow MacTV under macOS **Privacy & Security → Accessibility**. When you switch to headphones or built-in speakers, the volume keys return to normal system control.

<p align="center">
  <img src="docs/images/settings-live.png" width="480" alt="MacTV settings in Chinese: select the volume control device, enable keyboard volume keys, and view connection diagnostics">
</p>

## Before you start

Requires an **Apple Silicon Mac, macOS 14+, and a CEC-capable HDMI connection**. Apple requires macOS 14.4 or later for the supported adapter connection. Not every Mac HDMI port or dock supports CEC; see [Apple’s supported hardware](https://support.apple.com/en-us/108928).

This is an early release. TVs respond differently to menu and input commands; **a command being sent does not mean the TV acted on it**. Switching back to the Mac has been tested successfully on a REDMI display. Its quick settings panel and direct switching to other inputs still need compatibility work. HDMI 1–4 are preset requests, not four detected input devices. See the [compatibility notes (Chinese)](docs/COMPATIBILITY.md).

MacTV sends CEC commands through private macOS IOKit interfaces, which may change with system updates. It does not depend on BetterDisplay, offer Wi-Fi control, or include telemetry. Diagnostic logs stay on your Mac; check them for device names before sharing.

## Build it yourself

Open `MacTV.xcodeproj`, select the **MacTV** scheme, choose your developer team under Signing & Capabilities, and run the app or use **Product → Archive**.

```sh
swift test
python3 scripts/validate-localizations.py
```

The Xcode project is included in the repository. After editing `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen). See the [release guide (Chinese)](docs/RELEASING.md) for signing, notarization, and verification steps for public distribution.

---

<p align="center">SwiftUI + AppKit · HDMI-CEC · <a href="LICENSE">MIT</a></p>
