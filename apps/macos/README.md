# Clefwise for macOS

The native macOS version of [Clefwise](../../README.md), for learning to read notes on the staff.
A note appears on a treble or bass staff; name it as fast as you can.

## Run it

From this folder (`apps/macos`):

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
  - **Pause** (or Space) during a round stops the clock and hides the note until you press
    Resume (or Space again). Paused time doesn't count towards the sprint, your response times
    or your practice time. Switching to another app mid-round pauses it too; it waits for you
    to resume.
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

Keyboard: Space/Return start · Space pause/resume during a round · Esc stop · H hints · K key names (piano) · M mute · ⌘O open a piece.

## Practise a piece

Open a MusicXML file (`.musicxml`, `.xml` or compressed `.mxl`; in MuseScore use File → Export)
with **File → Open Piece…** (⌘O), the **Practise a piece…** button, or by dropping it on the
window. Then pick the part, the **hand** (right = upper staff, left = lower, or both), **in order**
or **shuffled**, the **bar to start at**, and whether to ask **one note per chord** (top note in
the right hand, bottom note in the left). Clef, key signature and range come from the piece, so
those toolbar settings are greyed out; Mode, note names and the answer method still apply.

- **The whole bar is on the staff**, as on the printed page:
  - **What's drawn:** note values, rests, chords, ties and dots; both staves with a brace for both
    hands. The note to name is highlighted in blue, and notes you've answered fade.
  - **Bar strip:** under the staff it shows where you are in the piece.
  - **Sharps and flats:** printed only where the sheet prints them. A sign holds until the bar
    line, so an F♯ whose sharp came earlier in the bar is still F♯.
  - **Turning it off:** untick **Show the whole bar** in the piece panel to go back to one note
    at a time. Each note then carries any sign it needs.
- **Order and pace:**
  - Notes come in reading order, chords bottom to top, both hands lower staff first.
  - Rests and tied-over notes are drawn but not asked.
  - In Practice mode the round ends with the last note; a 60s Sprint wraps back to the start bar.
- Under an 8va/8vb line the note is drawn where it's written, with the mark; the piano answer is
  the key that actually sounds.
- Notes in other clefs (C clefs, octave clefs) and double sharps/flats are left out, with a note
  saying how many. Repeats aren't expanded.
- The last piece reopens at launch. **Back to random notes** returns to normal practice.

Notes you've missed recently come up more often (based on your last 8 tries at each note), so
practice concentrates on what you don't know yet. History, best scores and settings are stored in
`UserDefaults`; reset everything with `defaults delete local.clefwise`.

## Progress dashboard

**Window → Progress** (⇧⌘P), or the **Progress** button next to the hints and mute buttons, opens
a dashboard built from your usage data. Pick a range (last 7 / 30 / 90 days, all time) and a clef;
everything on the page follows that choice.

- **Overview**: practice time, notes answered, accuracy, typical response time (median to a
  right answer) against the previous period, and your day streak.
- **Over time**: accuracy and response time per day (per week past six weeks).
- **Note map**: every line and space per clef, laid out like the staff, darker for better known;
  hollow where there are fewer than 5 answers yet.
- **Notes to work on**: your most-missed and slowest notes, sharps and flats included.
- **Practice calendar**, **how you answer** (by answer method and naming system), **pieces** bar by
  bar, and **recent rounds**.

Every chart has a **Table** view with the numbers. The dashboard refreshes when a round ends and
can stay open beside the game.

## Your usage data

Everything you do is recorded locally for analysing your progress: every question and answer
(note, clef, key, response time in ms, how you answered, each keystroke with its timing), every
round with its settings and result, settings changes, pieces opened, and app sessions (launch,
quit, time the app was in front). Nothing leaves your Mac.

- Stored as one JSON Lines file per day in `~/Library/Application Support/Clefwise/Usage/`,
  only ever appended to.
- **File → Export Usage Data…** (⇧⌘E) saves a zip with the raw event files, `answers.csv`,
  `rounds.csv`, `sessions.csv`, your current settings and stats, and `SCHEMA.md` describing every
  field (with snippets for pandas, DuckDB and jq). **File → Show Usage Data in Finder** opens the
  folder.
- To start the log afresh, quit the app and delete that folder.

## Layout

```
Sources/Clefwise/
  ClefwiseApp.swift   app entry, window, File → Open Piece…
  ContentView.swift   UI: stats, staff card, start/summary panels, answer keys
  PiecePanel.swift    piece setup panel, opening and dropping files
  StaffView.swift     one note on a staff: clef, key signature, ledger lines, 8va and hints (Canvas)
  BarStaffView.swift  a whole bar of a piece (one staff or a grand staff), laid out by BarLayout.swift
  StaffDrawing.swift  drawing shared by both: staff geometry, glyphs, key signatures, hints, pill
  NoteShapes.swift    note heads, flags, rests, brace and ties as paths
  BarDisplay.swift    what the bar view shows: the bar, its staves, the note asked, notes answered
  PianoKeyboard.swift piano answer input
  TypingPad.swift     keyboard (typing) answer input
  Game.swift          round logic (random and piece rounds), adaptive note picking, persistence
  Music.swift         pitches, accidentals, key signatures, clefs, ranges, naming systems
  Song.swift          a piece read from MusicXML: notes to ask, and every bar as drawn
  MusicXML.swift      MusicXML / .mxl importer
  UsageEvents.swift   what the usage log records (event format)
  UsageLog.swift      the usage log on disk (daily JSON Lines files)
  UsageExport.swift   export zip: raw events, CSV tables, saved settings and stats
  UsageSchemaDoc.swift SCHEMA.md text included in exports
  AppUsage.swift      app lifecycle and UI-click logging, usage data menu items
  Dashboard/          the Progress window: ProgressAnalyzer turns the usage log into a
                      ProgressReport; ProgressStore loads it off the main thread; DashboardView
                      and one file per section draw it (palette and card chrome in DashboardTheme)
  Synth.swift         tiny additive synth for note playback
  Theme.swift         colors
Tests/ClefwiseTests/  Swift Testing tests (`swift test`); the MusicXML test scores they read are
                      shared by every version, in ../../spec/fixtures/scores
Resources/AppIcon.icns
build-app.sh          packages the release binary as a .app
```
