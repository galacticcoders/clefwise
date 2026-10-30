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
- Pick a **key** (C major, up to 5 sharps or 5 flats, or a random key each round) and tick
  **Accidentals** to also get notes with a printed ♯, ♭ or ♮ now and then. Answer with the full
  name, so in G major an unmarked F is F♯. Letters and solfège go by spelling (F♯ isn't G♭);
  sargam goes by swara (komal Re, Ga, Dha, Ni and tivra Ma). With C major and no accidentals the
  app works exactly as before.
- Pick **note names**: letters (C D E F G A B), solfège (Do Re Mi Fa Sol La Si) or sargam
  (Sa Re Ga Ma Pa Dha Ni). Solfège and sargam are used as fixed names: Do = Sa = C.
- Pick how to **answer** with the *Answer with* switch under the answer area:
  - *Note buttons*: click a name, press **1–7** (button position), or with letter names type
    **C D E F G A B**. Any octave counts. When notes can be sharp or flat, ♭ and ♯ buttons
    (komal/tivra in sargam) appear either side; arm one (or press **-** / **#**) and then pick
    the letter.
  - *Piano*: click the exact key, so the octave has to be right too. The keyboard covers whole
    octaves for the current clef and range. Keys are blank unless you tick *Show key names* (K),
    which names white and black keys (C♯/D♭…, Do♯/Re♭…, or komal/tivra swaras in sargam; black
    keys stay blank when the keyboard is too wide to fit them). Black keys become answers when
    notes can be sharp or flat. A miss lights up the right key and tells you if you only got the
    octave wrong.
  - *Keyboard*: type the note's name in the current naming system (`c`, `sol`, `dha`); it
    answers as soon as a whole name is typed. Add `#` for sharp or `b` for flat (`f#`, `sib`;
    sargam `reb` = komal Re, `ma#` = tivra Ma). A name that could still take a sign (`f`) waits
    for Return. Keys that can't continue any name are ignored with a shake, and Backspace fixes
    typos; neither counts as a miss. Any octave counts. During a round every letter types, so H
    and M only work as shortcuts between rounds.

  Each answer method, key and accidentals setting keeps its own best scores.
- A correct answer plays the note. A miss shows the note in red with its name and highlights the
  right key for a moment.
- **Hints** (H) prints the name of every line and space and, with letter names, shows the
  mnemonics (Every Good Boy Does Fine / FACE, Good Boys Do Fine Always / All Cows Eat Grass).

Keyboard: Space/Return start · Esc stop · H hints · K key names (piano) · M mute · ⌘O open a piece.

## Practise a piece

Open a MusicXML file (`.musicxml`, `.xml` or compressed `.mxl`; in MuseScore use File → Export)
with **File → Open Piece…** (⌘O), the **Practise a piece…** button, or by dropping it on the
window. Then pick the part, the **hand** (right = upper staff, left = lower, or both), **in order**
or **shuffled**, the **bar to start at**, and whether to ask **one note per chord** (top note in
the right hand, bottom note in the left). Clef, key signature and range come from the piece, so
those toolbar settings are greyed out; Mode, note names and the answer method still apply.

- Notes come one at a time in reading order; chords bottom to top, both hands lower staff first.
  Rests and tied continuations are skipped. In Practice mode the round ends with the last note;
  a 60s Sprint wraps back to the start bar.
- Since the rest of the bar isn't on screen, a note whose sharp or flat comes from earlier in the
  bar gets its sign printed.
- Under an 8va/8vb line the note is drawn where it's written, with the mark; the piano answer is
  the key that actually sounds.
- Notes in other clefs (C clefs, octave clefs) and double sharps/flats are left out, with a note
  saying how many. Repeats aren't expanded.
- The last piece reopens at launch. **Back to random notes** returns to normal practice.

Notes you've missed recently come up more often (based on your last 8 tries at each note), so
practice concentrates on what you don't know yet. History, best scores and settings are stored in
`UserDefaults`; reset everything with `defaults delete local.clefwise`.

## Layout

```
Sources/Clefwise/
  ClefwiseApp.swift   app entry, window, File → Open Piece…
  ContentView.swift   UI: stats, staff card, start/summary panels, answer keys
  PiecePanel.swift    piece setup panel, opening and dropping files
  StaffView.swift     staff, clef, key signature, note, ledger lines, 8va and hints (Canvas)
  PianoKeyboard.swift piano answer input
  TypingPad.swift     keyboard (typing) answer input
  Game.swift          round logic (random and piece rounds), adaptive note picking, persistence
  Music.swift         pitches, accidentals, key signatures, clefs, ranges, naming systems
  Song.swift          a piece read from MusicXML
  MusicXML.swift      MusicXML / .mxl importer
  Synth.swift         tiny additive synth for note playback
  Theme.swift         colors
Tests/ClefwiseTests/  Swift Testing tests (`swift test`), with hand-written MusicXML fixtures
Resources/AppIcon.icns
build-app.sh          packages the release binary as a .app
```
