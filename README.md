# clipi

A keyboard-first clipboard manager for macOS. Press **⌥⌘V** anywhere — clipi opens under your cursor with your last 10 copies. Pick one with the arrow keys (or `⌘1`–`⌘9`), hit `↵`, and the item is pasted back into whatever app you came from.

Built to be small, fast, and out-of-the-way. No subscription, no telemetry, no cloud, no Electron.

## Install

Grab the latest signed + notarized DMG from [Releases](https://github.com/navjots35/clipi/releases) and drag `clipi.app` into `Applications`. macOS 13 (Ventura) or newer.

First launch:

1. A welcome card explains the keyboard model.
2. macOS prompts for **Accessibility** access. Grant it — clipi needs it to position the panel at your text caret and to synthesize the paste keystroke into the previously focused app.
3. Press **⌥⌘V** anywhere. That's it.

## Privacy

The clipboard is one of the most sensitive surfaces on your machine. clipi is paranoid by default:

- **Password managers are excluded out of the box** — 1Password, Bitwarden, Keychain Access, LastPass, Dashlane, Proton Pass.
- **Browser password fields are detected via Accessibility** (`AXSecureTextField`) and not captured, so banking sites and login forms never end up in your history.
- **Items marked `org.nspasteboard.ConcealedType`** by other apps are honored — well-behaved password managers self-mark and we respect that.
- **Terminal & iTerm copies are stored as plain text only** so escape sequences and ANSI noise can't sneak into your history.
- **History is local-first** — JSON file at `~/Library/Application Support/clipi/history.json`, never sent anywhere.

You can edit the per-app rules in **Settings → Per-app rules** (⌘, in the panel, or via the menu-bar icon).

## Keyboard

Inside the panel:

| Key | Action |
|---|---|
| `↑` `↓` | Move selection |
| `↵` | Paste with original formatting |
| `⌘↵` | Paste as plain text (strips rich formatting) |
| `⌘1`–`⌘9`, `⌘0` | Jump-paste an item by position |
| `esc` | Close (or clear search if typing) |
| `⌘,` | Open Settings |
| Type to search | Fuzzy filter across content + source app name |

## Build from source

Requires the Xcode command-line tools (Swift 6, the Swift toolchain that ships with Xcode 15+).

```sh
git clone https://github.com/navjots35/clipi.git
cd clipi
./scripts/build.sh         # ad-hoc signed dev build
open build/clipi.app
```

For a release build, see `scripts/release.sh` — it handles Developer ID signing, Apple notarization, stapling, and DMG packaging end to end.

## Architecture (brief)

- `Sources/Clipi/Models/` — `ClipboardStore`, `ClipboardItem`, `AppSettings`, JSON persistence.
- `Sources/Clipi/Services/` — `PasteboardWatcher` (polls `NSPasteboard.changeCount`), `HotkeyManager` (Carbon `RegisterEventHotKey` for the global ⌥⌘V), `Paster` (writes pasteboard + synthesizes ⌘V via `CGEvent.post`), `SecureFieldDetector` (AX role check), `CaretLocator` (AX-based caret position for "panel under cursor").
- `Sources/Clipi/UI/` — SwiftUI panel, settings window, onboarding card. `PanelController` hosts the SwiftUI panel inside a non-activating `NSPanel` so summoning clipi never steals activation from your current app.

## Status

Early. Working well enough to be the author's daily driver. Things still on the list:

- Custom hotkey recording (currently fixed at ⌥⌘V)
- Sparkle-based auto-updates
- Theme / accent customization
- Item detail / preview pane (image preview, copy-as-actions)

## Acknowledgements

Designed with [Claude Design](https://claude.ai/design); implemented in collaboration with Claude Code. The design intent is documented in `clipi/project/Clipi.html` of the original handoff bundle.
