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

- Pick a **clef** (Treble, Bass, Both) in the toolbar, and practise at your own pace.
  - On the start panel, **Length** sets how a round ends: *No limit* (until you stop), *Time* (2,
    5, 10, 15 or 30 minutes) or *Notes* (50, 100, 250, 500 or 1 000 notes, right or wrong). Pieces
    ignore it: a piece ends with its last note.
  - **Pause** (or Space) during a round stops the clock and hides the note until you press
    Resume (or Space again). Paused time doesn't count towards a timed round, your response times
    or your practice time. Switching to another app mid-round pauses it too; it waits for you
    to resume.
  - If Clefwise closes unexpectedly mid-round (a crash, a force quit, a flat battery), the round
    comes back paused where it was at the next launch, with the note that was on screen. If it
    closes again once you carry on, before your next answer, the round ends there. Quitting (⌘Q)
    ends a round as before.
- Pick the **notes** on the start panel, under the staff: tick any mix of *Above the staff*,
  *On the staff* (lines and spaces, the default) and *Below the staff*. *Ledger lines* (1 to 5)
  sets how far above and below go: one line adds middle C and friends below the treble staff.
- Pick a **key** (C major, up to 5 sharps or 5 flats, or a random key each round) and tick
  **Accidentals** to also get notes with a printed ♯, ♭ or ♮ now and then. Answer with the full
  name, so in G major an unmarked F is F♯. Letters and solfège go by spelling (F♯ isn't G♭);
  sargam goes by swara (komal Re, Ga, Dha, Ni and tivra Ma). With C major and no accidentals the
  app works exactly as before.
- Pick **note names**: letters (C D E F G A B), solfège (Do Re Mi Fa Sol La Si) or sargam
  (Sa Re Ga Ma Pa Dha Ni). Solfège and sargam are used as fixed names: Do = Sa = C.
- **Light or dark**: Clefwise follows macOS's appearance. **View ▸ Appearance** keeps it Light or
  Dark whatever macOS is set to. In dark mode the staff is dark with light notes, the piano keeps
  its white keys (dimmed), and the Progress window's charts use colours checked for the dark
  background.
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
    sargam `reb` = komal Re, `ma#` = tivra Ma). No Return needed: a right name goes in at once and
    a wrong one is marked at once; only the right letter typed without its sign (`f` for F♯)
    waits for the sign (Return answers it as typed). Keys that can't continue any name are
    ignored with a shake, and Backspace fixes typos; neither counts as a miss. Any octave counts.
    During a round every letter types, so H and M only work as shortcuts between rounds.
- A correct answer plays the note. A miss shows the note in red with its name and highlights the
  right key for a moment.
- **Hints** (H) prints the name of every line and space and, with letter names, shows the
  mnemonics (Every Good Boy Does Fine / FACE, Good Boys Do Fine Always / All Cows Eat Grass).

Keyboard: Space/Return start · Space pause/resume during a round · Esc stop · H hints · K key names (piano) · M mute · ⌘O open a piece · ⇧⌘O your pieces.

## Practise a piece

Open a MusicXML file (`.musicxml`, `.xml` or compressed `.mxl`; in MuseScore use File → Export)
with **File → Open Piece…** (⌘O), the **Practise a piece…** button, or by dropping it on the
window. Then pick the part, the **hand** (right = upper staff, left = lower, or both), **in order**
or **shuffled**, the **bar to start at**, and how to ask **chords**:
- **Note by note**, bottom to top; this is the default.
- **Top / bottom note**: only the top note in the right hand and the bottom note in the left.
- **All together**: every note struck at that moment is one answer, so with both hands that's
  both staves.
  - **Answering:** type the names back to back in any order, one name per note ("sisol", or
    "dodo" for two Cs). On the note buttons, pick the names; they appear as chips, and you click a
    chip to remove it. On the piano, click the keys; clicking a key again unselects it.
  - **Judging:** each note is marked right (green) or wrong (red, with its name) on its own. A
    fully right chord plays all its notes at once. Clef, key signature and range come from the piece, so
those toolbar settings are greyed out; note names and the answer method still apply.

- **The whole bar is on the staff**, as on the printed page:
  - **What's drawn:** engraved with the Bravura music font: note values, beams (as the score
    writes them, or by the beat when it has none), rests, chords, ties, dots and the time signature;
    both staves with a brace for both hands. The note to name is highlighted in blue, and notes you've answered fade.
  - **Bar strip:** under the staff it shows where you are in the piece.
  - **Sharps and flats:** printed only where the sheet prints them. A sign holds until the bar
    line, so an F♯ whose sharp came earlier in the bar is still F♯.
  - **Turning it off:** untick **Show the whole bar** in the piece panel to go back to one note
    at a time. Each note then carries any sign it needs.
- **Order and pace:**
  - Notes come in reading order, chords bottom to top, both hands lower staff first.
  - Rests and tied-over notes are drawn but not asked.
  - The round ends with the last note.
- Under an 8va/8vb line the note is drawn where it's written, with the mark; the piano answer is
  the key that actually sounds.
- Notes in other clefs (C clefs, octave clefs) and double sharps/flats are left out, with a note
  saying how many. Repeats aren't expanded.
- The last piece reopens at launch. **Back to random notes** returns to normal practice.

### Your pieces

Every piece you open is kept, so you can practise it again without looking for the file:
- **Where they are:** the latest under **Your pieces** on the start panel, the others through
  **All pieces…** there, **File → Open Recent Piece**, **File → All Pieces…** (⇧⌘O), or the piece
  panel's **Open another…** menu. The full list can be searched once it's longer than eight.
- **Each piece keeps its own settings** (part, hand, order, start bar, chords, whole bar), so it
  comes back as you left it.
- **Clefwise keeps its own copy** in `~/Library/Application Support/Clefwise/` (and one in your
  practice journal), so moving or deleting the original doesn't matter. Opening the same file again, from anywhere, is the same
  piece; a score exported again to the same place replaces the copy and keeps the settings.
- **Remove…** in the list forgets a piece and its copy; the original file isn't touched.

Notes you've missed recently come up more often (based on your last 8 tries at each note), so
practice concentrates on what you don't know yet. History comes from your practice journal
(below); settings are stored in `UserDefaults`, one set per journal. To start afresh, make
a new journal.

## Progress dashboard

**Window → Progress** (⇧⌘P), or the **Progress** button next to the hints and mute buttons, opens
a dashboard built from your practice journal. Pick a range (last 7 / 30 / 90 days, all time) and a clef;
everything on the page follows that choice.

- **Overview**: practice time, notes answered, accuracy, typical response time (median to a
  right answer) against the previous period, and your day streak.
- **Over time**: accuracy, response time, and how much your times vary (the spread of the middle
  half of right answers), per day (per week past six weeks).
- **Becoming automatic**: the signs that naming a note no longer takes working out, each with a
  plain-language reading: how long your answers take (this period against the one before), mistakes
  by speed (are they the rushed ones?), and how the distance from the note before changes your time.
- **Note map**: every line and space per clef, laid out like the staff, darker for better known;
  hollow where there are fewer than 5 answers yet.
- **Practice map**, beside it and laid out the same: how often each line and space has come up,
  in orange, darker for more; hollow where it never has. Its table ranks them from most to least
  practised.
- **Speed map**, laid out the same: each line and space's median time over its last 20 right
  answers, so the notes that are still slow stand out; hollow until a place has 5 right answers.
- **Notes to work on**: your most-missed and slowest notes, sharps and flats included.
- **Practice calendar**, **how you answer** (by answer method and naming system), **pieces** bar by
  bar, and **recent rounds**.

Every chart has a **Table** view with the numbers. The dashboard refreshes whenever practice
reaches the journal (a round ending, or another device's) and can stay open beside the game.

## Your practice journal

Clefwise keeps your practice in a *practice journal*: a folder of plain files that's yours, the
way Obsidian keeps notes in a folder. There's no account and no Clefwise server.

- **Where:** at first launch Clefwise asks for the journal's name and place (by default
  `~/Documents/Clefwise Journal`). Back it up or sync it however you like: keep it in iCloud Drive
  or Dropbox, or share it with Syncthing. You can move or rename it in Finder.
- **What's in it:** each finished practice run is one file in `runs/<year>/<month>/` (its lines
  from the usage log, below). Your pieces go in `pieces/`, named by their SHA-256, and changes to
  the list in `events/`. Files are only ever added, never changed. A run with no answers gets no
  file.
- **It's the source:** the dashboard and which notes come up more often are both worked out from
  the journal.
- **From your other devices:** in a folder synced by iCloud Drive, Dropbox or Syncthing, practice
  from another device comes in while Clefwise is open: the dashboard and note picking follow it,
  and a piece added, changed or removed there is here too. New stats wait for the round to end.
- **One journal per person,** so several people can share a Mac, still with no accounts. Each
  journal keeps its own settings and pieces; a new one starts with the default
  settings. The window title names the journal in use.
  - **Switch** between rounds with **Journal: <name>** on the start panel or **File → Switch
    Journal**. The start panel's menu and the File menu also have **New Journal…** and **Open
    Journal…** (a folder with `clefwise.json` in it).
  - **Remove "<name>" from List…** (on the start panel) only forgets it on this Mac; the folder
    stays as it is.
- **Practice so far:** when your first journal is made, your usage log and pieces so far are
  copied into it (only that one: it's one person's practice).
- **File → Show Journal in Finder** opens it, during a round too. If Clefwise can't find it (a
  disk unplugged, the folder moved out of reach), it offers **Locate…**, **Create New…** or
  another of your journals; finished runs wait on your Mac until it's back.
- The format is in [spec/practice-journal.md](../../spec/practice-journal.md).

## Your usage data

Everything you do is recorded locally for analysing your progress: every question and answer
(note, clef, key, response time in ms, how you answered, each keystroke with its timing), every
round with its settings and result, settings changes, pieces opened, and app sessions (launch,
quit, time the app was in front). Nothing leaves your Mac, unless you keep your practice journal
in a synced folder.

- Stored as one JSON Lines file per day in `~/Library/Application Support/Clefwise/Usage/`,
  only ever appended to.
- **File → Export Usage Data…** (⇧⌘E) saves a zip with the raw event files, `answers.csv`,
  `rounds.csv`, `sessions.csv`, your current settings and stats, your list of pieces, and `SCHEMA.md` describing every
  field (with snippets for pandas, DuckDB and jq). **File → Show Usage Data in Finder** opens the
  folder.
- To start the log afresh, quit the app and delete that folder.

## Layout

```
Sources/Clefwise/
  ClefwiseApp.swift   app entry, window, File → Open Piece…
  ContentView.swift   UI: stats, staff card, start/summary panels, answer keys
  PiecePanel.swift    piece setup panel, opening and dropping files
  PieceLibrary.swift  the pieces kept to practise again: copies, index, settings per piece
  LibraryView.swift   Your pieces on the start panel, and the list of all of them
  StaffView.swift     one note on a staff: clef, key signature, ledger lines, 8va and hints (Canvas)
  BarStaffView.swift  a whole bar of a piece (one staff or a grand staff), laid out by BarLayout.swift
  StaffDrawing.swift  drawing shared by both: staff geometry, glyphs, key signatures, hints, pill
  NoteShapes.swift    note heads, flags, rests, brace and ties as paths
  BarDisplay.swift    what the bar view shows: the bar, its staves, the note asked, notes answered
  PianoKeyboard.swift piano answer input
  TypingPad.swift     keyboard (typing) answer input
  Game.swift          round logic (random and piece rounds), adaptive note picking, persistence
  RoundReplay.swift   a round as its run file tells it, to bring it back after a crash
  Music.swift         pitches, accidentals, key signatures, clefs, ranges, naming systems
  Song.swift          a piece read from MusicXML: notes to ask, and every bar as drawn
  MusicXML.swift      MusicXML / .mxl importer
  UsageEvents.swift   what the usage log records (event format)
  UsageLog.swift      the usage log on disk (daily JSON Lines files)
  UsageExport.swift   export zip: raw events, CSV tables, saved settings and stats
  UsageSchemaDoc.swift SCHEMA.md text included in exports
  AppUsage.swift      app lifecycle and UI-click logging, usage data menu items
  AppModel.swift      the journal in use with its game, pieces and dashboard; switching journals
  Dashboard/          the Progress window: ProgressAnalyzer turns the practice journal into a
                      ProgressReport; ProgressStore loads it off the main thread; DashboardView
                      and one file per section draw it (palette and card chrome in DashboardTheme)
  Journal/            the practice journal: run files and their writer, the folder, the journals
                      this Mac knows (JournalRegistry) and its state for each, the sheet and alerts,
                      reading it (JournalReader) and watching it for changes (JournalWatcher),
                      bringing in the old log (LogImport), note stats from it (JournalProjection)
  Synth.swift         tiny additive synth for note playback
  Theme.swift         colors
Tests/ClefwiseTests/  Swift Testing tests (`swift test`); the MusicXML test scores they read are
                      shared by every version, in ../../spec/fixtures/scores
Resources/AppIcon.icns
Resources/Fonts/      the Bravura music font (SIL Open Font License, see OFL.txt), unmodified
build-app.sh          packages the release binary as a .app
```
