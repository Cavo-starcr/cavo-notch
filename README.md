# CAVO Notch

*English · [Русский](README.ru.md)*

The MacBook notch as a working tool. A native SwiftUI/AppKit app: invisible at
rest, and on hover it unfolds downwards into a panel with a player, a shelf for
files, clipboard history, snippets, your next meetings, a translator, scratch
notes and a timer.

**[Download for macOS](https://cavo.one/tools/notch)** — macOS 15 or newer,
Apple Silicon. The first launch needs one command, [here is why](#installation).

```
0.0 % CPU at rest  ·  ≈40 MB  ·  one permission, and only on a button
```

## What it does

| Tab | What it does |
|---|---|
| **Music** | Artwork, track, artist, a scrubber that seeks, prev / play-pause / next. The source is **anything** macOS itself can see — a player, a browser tab, any app |
| **Shelf** | Drag files into the notch and they stay there until needed; drag a card out and the file goes wherever it is dropped. ⌘-click picks several and the whole group drags at once. Each card also carries Quick Look (space bar or the eye button), copy-path, share through AirDrop, rename in place, and compress — one card into its own archive, a selection into one flat `Archive.zip`. A screenshot taken to the clipboard is saved as a file and lands here too, including one copied from an iPhone |
| **Clipboard** | The last 40 copies; a click puts an entry back on the clipboard |
| **Snippets** | A hand-kept list of what you are tired of retyping — an address, a phone number, an email. The same list lives in `~/Library/Application Support/CAVO Notch/snippets.json` and can be edited there instead |
| **Calendar** | The next meeting a week ahead: how long until it starts and a button that joins the call — Zoom, Meet, Teams and others |
| **Translate** | Type on the left, the translation appears on the right — by itself, offline, using macOS's own facilities |
| **Notes** | Scratch, on the right rail: jot something down, come back, delete it or carry it off through the clipboard. Blank notes sweep themselves out |
| **Timer** | 5 / 10 / 25 / 45 minutes on one press, or a pomodoro that runs 25 of focus and hands over to 5 of break by itself. Pause, +1 min, stop. While it runs the remaining time sits next to the menu bar icon; it ends with a chime and a notification. A run outlives a relaunch |

The panel opens when the pointer reaches the notch and collapses when it leaves.
Tabs switch on hover as well — but only if the pointer has come to rest on the
icon: one passing through switches nothing. During a file drag the panel opens by
itself and goes straight to the shelf. The menu bar icon toggles the panel, hides
the contents of any tab for screen sharing, switches launch at login, and quits.

The app works on Macs without a notch too: the panel then treats a 180 × 24 pt
area at the top centre of the screen as one.

## Installation

Download the DMG, drag **CAVO Notch** into Applications, then run this once:

```bash
xattr -cr "/Applications/CAVO Notch.app"
```

macOS may otherwise say the app is damaged. It is not. Apple charges for
Developer ID signing and notarisation; until that is in place, anything
downloaded from the web and not notarised gets a quarantine flag, and recent
macOS versions word the refusal as "damaged" rather than "unidentified
developer". The command above removes that flag from this one app and changes
nothing else on the system. You only need it once per install.

A signed and notarised build is coming — then the command goes away.

## Requirements

- macOS 15 or newer (the Translate tab runs on Translation.framework)
- Apple Silicon
- Swift 6 toolchain to build it yourself (Command Line Tools are enough, the
  full Xcode is not needed)

## Building

```bash
git clone https://github.com/cavo-one/cavo-notch.git
cd cavo-notch
./Scripts/bundle.sh          # swift build + assemble the .app + ad-hoc sign
open "build/CAVO Notch.app"
```

`./Scripts/dmg.sh` builds the disk image. `swift Scripts/make-icon.swift
Resources/AppIcon.icns` redraws the icon — it is generated from code, so there is
no binary asset to keep in sync.

## Privacy

Nothing leaves the machine. No accounts, no telemetry, no network calls of its
own. The one permission the app ever asks for is Calendar, and only when you
press the button on the Calendar tab. Track information comes from macOS's own
Now Playing feed rather than from any player's API.

Screenshots saved from the clipboard live in
`~/Library/Application Support/CAVO Notch/Screenshots` and are never deleted
behind your back — the menu bar item shows the folder's size and clears it on
request.

## Credits and licence

MIT. Built on the open-source [Cyclop](https://github.com/akalikbergenov/cyclop)
by akalikbergenov, whose copyright stands alongside ours in [LICENSE](LICENSE).
The timer, the shelf actions, the CAVO design and this build are ours.
