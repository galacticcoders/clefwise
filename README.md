# Clefwise

A small native macOS app for learning to read notes on the staff. A note appears on a treble or
bass staff; name it as fast as you can.

## Run it

```sh
./build-app.sh --open      # build build/Clefwise.app and launch it
./build-app.sh --install   # build and copy to ~/Applications
swift run                  # quick dev run without bundling
```

Requires macOS 14+ and Xcode (or the Swift toolchain).

## How to play

- Pick a **clef** (Treble, Bass, Both), a **note range** and a **mode** in the toolbar.
  - *On the staff*: lines and spaces only. *+1 ledger line* adds middle C and friends.
    *+3 ledger lines* goes three lines above and below.
  - *60s Sprint*: name as many notes as you can in a minute; best score is kept per clef/range.
  - *Practice*: no clock; press Stop (Esc) to see your summary.
- Pick **note names**: letters (C D E F G A B), solfège (Do Re Mi Fa Sol La Si) or sargam
  (Sa Re Ga Ma Pa Dha Ni). Solfège and sargam are used as fixed names: Do = Sa = C.
- Pick how to **answer** with the *Answer with* switch under the answer area:
  - *Note buttons*: click a name, press **1–7** (button position), or with letter names type
    **C D E F G A B**. Any octave counts.
  - *Piano*: click the exact key, so the octave has to be right too. The keyboard covers whole
    octaves for the current clef and range. Keys are blank unless you tick *Show key names* (K),
    which names white and black keys (C♯/D♭…, Do♯/Re♭…, or komal/tivra swaras in sargam; black
    keys stay blank when the keyboard is too wide to fit them). A miss lights up the right key
    and tells you if you only got the octave wrong. Piano rounds keep their own best scores.
- A correct answer plays the note. A miss shows the note in red with its name and highlights the
  right key for a moment.
- **Hints** (H) prints the name of every line and space and, with letter names, shows the
  mnemonics (Every Good Boy Does Fine / FACE, Good Boys Do Fine Always / All Cows Eat Grass).

Keyboard: Space/Return start · Esc stop · H hints · K key names (piano) · M mute.

Notes you've missed recently come up more often (based on your last 8 tries at each note), so
practice concentrates on what you don't know yet. History, best scores and settings are stored in
`UserDefaults`; reset everything with `defaults delete local.clefwise`.

## Layout

```
Sources/Clefwise/
  ClefwiseApp.swift   app entry + window
  ContentView.swift   UI: stats, staff card, start/summary panels, answer keys
  StaffView.swift     staff, clef, note, ledger lines and hint drawing (Canvas)
  PianoKeyboard.swift piano answer input
  Game.swift          round logic, adaptive note picking, persistence
  Music.swift         pitches, clefs, ranges
  Synth.swift         tiny additive synth for note playback
  Theme.swift         colors
Resources/AppIcon.icns
build-app.sh          packages the release binary as a .app
```
