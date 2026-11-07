# The practice journal

**Draft, 2026-11-06. The macOS app is being built to it; no release writes a journal yet.**

Every version of Clefwise keeps a person's practice in a *practice journal*: a folder of plain
files that they own, which the app works on, much as Obsidian works on a folder of notes. Files in
the journal are only ever added, never changed or deleted. Each finished practice run is one new
file. Everything the app shows is worked out from those files: the dashboard, note stats and the
piece library. This approach is called event sourcing: the files are the events, and the rest is a
projection of them.

## Where the journal lives

- **The user chooses.** At its first launch the app asks where to keep the journal, and suggests
  `~/Documents/Clefwise Journal`. The folder can be moved, renamed or copied like any other.
- **Backing up and syncing are the user's choice.** The folder can sit in iCloud Drive or Dropbox,
  or be shared with Syncthing, and every device that sees it has the same practice history (see
  Folder sync). Git may come later as an option (see Optional git).
- **No accounts.** There's no sign-up and no Clefwise server.
- **One journal per person.** Each person keeps their own, and one computer can hold several (see
  Several journals).

## Principles

- **Files are only added.** A writer never changes, renames or deletes a file once it's in the
  journal. A mistake is fixed by adding a file that corrects it (see `runExcluded`). The one
  exception: a damaged score can be put back to the bytes its name says it has.
- **The files are the data.** Readers need only the files: any copy of the folder works as well as
  the original. File dates, a sync service's own records and (later) git history never feed a
  calculation, since copying or syncing can change them.
- **Times come from the events.** Every event line has its own `time` (UTC, to the millisecond),
  and a file's name has its start time. Durations (`responseMs`, `durationMs`, `pausedMs`,
  `activeMs`) come from the device's monotonic clock, so they stay right even if the wall clock
  changes during a run.
- **Every name is unique, or its content is fixed.** Two devices never create the same path with
  different bytes. A record's name includes its own id. A score's name is the hash of its bytes.
  The two root files are the same bytes everywhere. So in normal use syncing can't conflict;
  Folder sync and Optional git say what happens when something has gone wrong.
- **Old files stay readable forever.** Each file says which format it's in. A reader skips a file
  in a format newer than it knows, and tells the user to update the app.

## Layout

```
clefwise.json                                          marks the folder as a journal
.gitattributes                                         keeps git from changing any bytes
runs/2026/11/20261105T093112Z-<round id>.jsonl         one practice run
events/2026/11/20261105T101500Z-<event id>.jsonl       one event that isn't part of a run
pieces/<sha256>.musicxml                               a score, named by its bytes
```

- **Times in names** are the record's start time in UTC, in ISO 8601 basic format
  (`YYYYMMDDTHHMMSSZ`), so names sort by time and have no colons. The year and month folders are
  the same UTC date. Ids and hashes in names are lowercase. Compare ids without regard to case,
  because the events write UUIDs in uppercase.
- **`clefwise.json`** is exactly these bytes: `{"format":"clefwise-journal"}` and a line feed. It
  marks the folder as a Clefwise journal, so the app can tell one from any other folder. The app
  writes it, with `.gitattributes`, when it makes the journal.
- **`.gitattributes`** is exactly these bytes: `* -text` and a line feed. It matters only once the
  journal becomes a git repository (see Optional git). Then it keeps a clone made with
  `core.autocrlf` from changing line endings in the working copy, which would leave a score's bytes
  no longer matching the hash in its name. Writing it from the start means a journal never has to
  change to become a repository.
- **Nothing else belongs.** Readers ignore any file whose name doesn't fit this layout (see Folder
  sync).

## Run files (`runs/`)

One file per practice run, in [JSON Lines](https://jsonlines.org) (UTF-8, LF line endings):

1. **Line 1 is the header,** which says where the run comes from. It is not an event.
2. **The other lines are the events** the app logged from the run's `roundStarted` to its
   `roundEnded`, both included, in the order they were logged. Each is a usage-log line, unchanged:
   the envelope (`schema`, `type`, `id`, `time`, `session`, `sequence`) and the event's own fields.
   Events between the start and the end that have no round id belong in the file too, for example
   `appActivity` (switching apps pauses the round) and `settingChanged`. A run that came back after
   a crash (see below) spans two app sessions, with the second one's `appLaunched` between them;
   within the file, lines are in the order they were written.

The usage log's format is documented in the macOS app's data export, as `SCHEMA.md`, written from
`apps/macos/Sources/Clefwise/UsageSchemaDoc.swift`. It should move into `spec/` once a second
version writes it. For the journal it gained `roundRestored` and the `interrupted` end, with
`recordedAt` (see After a crash), and three fields in `roundStarted.piece` (see Pieces).

### The header

| Field | Meaning |
|---|---|
| `format` | The run-file format, now `1`. |
| `run` | Run files only: the run's id, the `round` in its events. |
| `event` | Event files only: the event's id, the `id` of its one event line. |
| `device` | An id this installation makes at its first launch and keeps locally; it never syncs. |
| `platform` | `macOS`, `iPadOS` or `Linux`. |
| `osVersion`, `model` | As in `appLaunched`. |
| `appVersion`, `build` | The app that wrote the file. |
| `locale`, `timeZone` | As in `appLaunched`. The time zone gives the run's local day, for streaks and the practice calendar. |

The header is one line of JSON with its keys sorted and its slashes unescaped (`Europe/Stockholm`).

### Writing a run

- **While the run goes on,** the app writes its events to a working file outside the journal, on
  the device. A crash then loses at most the line being written. Until it's placed in the journal,
  the file can still change. A device runs one round at a time, so it has at most one working file.
- **When the run ends,** the app places the finished file in the journal and doesn't touch it
  again. If the journal can't be found just then (a disk unplugged, the folder moved out of reach),
  the file waits on the device until it can be placed.
- **A run with no answers gets no file.** That covers a run started and stopped straight away.

### After a crash

A run ends when the user ends it (Stop or Esc), when it's finished (time up, all its notes done,
the end of the piece), when something else replaces it (opening or closing a piece, starting
over), or when the user quits the app (⌘Q, or shutting down or restarting the computer):
`roundEnded` with `reason` `appQuit`, as today.

A crash is any way the app stops without quitting: a crash, a force quit, the battery running out,
or iPadOS closing the app in the background. A crash ends nothing: the run comes back, paused, at
the next launch, however long ago that was.

At the next launch the app finds the working file still there. A run with no answers is dropped,
as usual. One that already ends with `roundEnded` (the app stopped just before placing it in the
journal) is placed as it is. Otherwise the app replays the file's events to rebuild the round:

- **Rebuilt:** the score, attempts, streak and best streak; the place in a piece; and the round
  time used, up to the round's last event. The seconds between that event and the crash are
  lost. Random notes and shuffled pieces need nothing more, since each pick depends only on the
  note stats (saved after every answer) and the note just asked.
- **Asked again:** the note that was on screen, exactly as it was (clef, pitch, printed sign, bar).
- **Not rebuilt:** a half-typed name or a half-entered chord.

The new session's `appLaunched` goes into the file, then `roundRestored`. From there it's a paused
round like any other. When the user carries on, the app logs `roundResumed` and then a
`questionShown` for the note that was on screen. That's a new question, with its own id, and its
response time is measured from when it appears again; the old question stays unanswered. The
round then ends as any round does, or comes back again after another crash.

The time between the crash and `roundRestored` counts as neither round time nor paused time.
`pausedMs` in the next `roundResumed` counts from `roundRestored`.

**`roundRestored`:** the round came back after a crash.

| Field | Meaning |
|---|---|
| `round` | The round's id. |
| `activeMs` | The round time brought back: up to the round's last event before the crash, pauses left out. A timed round has its limit minus this left. |
| `unansweredQuestion` | The id of the question on screen at the crash, if there was one. It's asked again as a new question when the round resumes. |

**When a round isn't brought back.** In two cases the app ends the round instead, with a
`roundEnded` whose `reason` is `interrupted`:
- **It crashed on the way back.** The app crashed while bringing the round back, or after the
  round resumed but before any new answer. Without this, a note that crashes the app would trap
  it in a loop. The file shows the second case: after its last `roundRestored` comes a
  `roundResumed` and no answer. For the first case the app keeps a note on the device while it
  rebuilds the round. A round that crashed while it was paused (for example, iPadOS closing the
  app in the background) is brought back again: its note never came up, so it can't be what
  crashed the app.
- **It can't be rebuilt.** For example, its piece isn't in the library any more, or a newer app
  wrote the file.

That `roundEnded` takes the time of the round's last event. Its duration, score and attempts are
counted from the events, and `recordedAt` says when the later launch wrote it. The file is then
placed in the journal as usual.

## Event files (`events/`)

These are the few events that change what the app knows without being part of a run. Each file
has the same header as a run file (with `event`, the event's id, in place of `run`), then exactly
one event line in the usage-log format.

| `type` | Fields | Meaning |
|---|---|---|
| `statsSnapshot` | as in the usage log | What a device knew before its usage log existed: its opening balance. Added once, when that device's old log is brought into the journal. Snapshots from versions until 2026-11-07 also have `bestScores`, the best scores of the 60-second sprint those versions had: a legacy field that readers ignore. |
| `pieceAdded` | `piece`, `title`, `fileName`, and optionally `libraryID` and `originalPath` | A score joined the library. `piece` is the hash of its file in `pieces/`, which is written first. `fileName` is the original file's name, without its folder. `libraryID` is the piece's entry in the adding device's piece library, and `originalPath` where the file was first opened from: the `libraryID` and `path` the usage log knows the piece by (see Bringing in the old usage log). |
| `pieceRevised` | `piece`, `file`, `title` | A new version of a piece, for example the score edited and exported again. `piece` is the id the piece was first added with, and `file` is the new file's hash. Both versions stay in `pieces/`. |
| `pieceRemoved` | `piece` | The piece left the library. Its file and its runs stay. Adding it again with `pieceAdded` brings it back. |
| `runExcluded` | `run`, `reason` (optional) | Leave this run out of every calculation, for example if the cat walked on the keyboard. The file stays. |

When library events disagree, the latest by `time` wins.

The macOS app writes no `runExcluded` yet. Readers still leave out any run one names.

## Pieces (`pieces/`)

Each score file is named by the SHA-256 of its bytes and keeps its extension in lowercase
(`.musicxml`, `.xml` or `.mxl`). The same score added on two devices is therefore one file. A
piece's id is the hash of the file it was first added with. Runs refer to pieces through new fields
in `roundStarted.piece`:

| Field | Meaning |
|---|---|
| `piece.id` | The piece, as in `pieceAdded`. |
| `piece.file` | The hash of the exact file practised. It differs from `id` after a `pieceRevised`. |
| `piece.staves` | Staves in the part, which the dashboard needs. Before the journal it was only in `pieceOpened`, outside the run. |

## What stays on each device

The journal leaves these out:
- **Settings,** including each piece's own practice settings. A run still records the settings it
  used, in `roundStarted.settings`.
- **Events outside runs:** launches and quits, window sizes, app switching and setting changes
  between runs. The local usage log keeps them.
- **Where the journal is, and the device id.** Each device keeps its own. Later, any git
  credentials too, in the keychain.
- **Projections:** the note stats and dashboard data worked out from the files. They can be cached
  on the device, but the cache must be rebuildable at any time from the files alone. Best sprint
  scores were one too, until the sprint went on 2026-11-07; they're no longer worked out, and the
  `bestScore` and `isNewBest` of old runs' `roundEnded`, like `statsSnapshot.bestScores`, are
  ignored.

## Several journals

A device may know several journals, one per person: for example a family sharing a Mac, each
practising in their own. The app works on one journal at a time, and switches between them only
between rounds.

- **Journals don't mix.** Runs, pieces and opening balances count only in their own journal, and
  each journal has its own piece library on the device.
- **What a device keeps about a journal stays on that device,** apart from what it keeps about any
  other: its settings and each piece's own practice settings, its projections (see What stays on
  each device), and its records waiting to be placed (see Writing a run). A journal new to the
  device starts with the default settings.
- **The device knows each journal by a local id** of its own, which never goes in the journal. The
  device id in headers is the same whichever journal the device writes to.
- **The old usage log is brought into only one journal:** the first one the device makes or uses
  (see Bringing in the old usage log). Its practice is one person's; a journal added later starts
  without it.

## Folder sync

Any service that syncs a folder can carry a journal: iCloud Drive, Dropbox, Syncthing, a network
drive, or a copy made by hand. Names never clash and files never change once written, so two
devices never write the same file differently, and there's nothing to merge.

Readers still have to expect what sync services do:
- **Files whose names don't fit the layout are ignored.** For example a service's conflicted copy
  (`… (conflicted copy).jsonl`), a duplicate (`… 2.jsonl`), `.DS_Store`, or a download in progress
  under a temporary name. A name fits only if it's exactly what the layout says: the right folder,
  the year and month folders of the time in the name, a lowercase id or hash, and the right
  extension.
- **Files may not be downloaded yet.** iCloud Drive can leave a placeholder in a file's place until
  it's opened (on macOS a hidden `.<name>.icloud` file, which doesn't fit the layout). A file that
  can't be read yet isn't an error: the reader asks for it to be downloaded, and counts it once
  it's there.
- **Files appear while the app is open.** Another device's runs can arrive at any time, in any
  order. Readers place them by their start time, so a run that arrives late still lands in its
  place. A file can also arrive before it's complete. Every run file in the journal ends with its
  `roundEnded`, so one that doesn't, or whose last line doesn't parse, is still arriving: read it
  again later. In the same way a `pieceAdded` can arrive before its score.

## Reading

- **Order of runs:** by their start time, then by id. A device whose clock is wrong misplaces only
  its own runs.
- **Skips:** files whose names don't fit the layout, runs named in a `runExcluded`, and lines that
  don't parse. Count the skipped lines, as the usage log's reader does.
- **Scores:** check a score's bytes against its name before using it. One that doesn't match is
  damaged: say so, and don't use it.
- **What to read:** a reader that keeps a cache only needs the files it hasn't read yet. Files never
  change, so a file it has already read whole stays read (see Folder sync for one still arriving).

## Bringing in the old usage log

Each device brings in its existing log once, when its first journal is made (into that journal
only: see Several journals). The log itself is only
read, never changed.
- **Runs:** its day files are split into run files using the rules above: everything a session
  logged from a `roundStarted` to its `roundEnded`. Each header comes from its session's
  `appLaunched`. Runs with no answers get no file. A run that never ended (the app crashed before
  runs could come back) gets an `interrupted` end.
- **Opening balance:** its `statsSnapshot` becomes an event file.
- **Library:** each piece in its library becomes its score in `pieces/` and a `pieceAdded`, with
  the entry's `libraryID` and `originalPath`.

Old runs have no `piece.id`: they name their piece by `libraryID` and `path` in
`roundStarted.piece`. Readers map them to a piece through the `pieceAdded` events: by `libraryID`,
or for runs logged before the library, by `path` against `originalPath`. A piece already
re-exported keeps only its latest bytes, so its older runs point at the newest file.

Bringing the log in again adds nothing that's already there: a run file is named by its round, the
snapshot by its event's own id, and a score already in `pieces/` isn't added again.

## Optional git (later)

Not part of the first version. A journal can later also be a git repository: for a history of
what was added, and for syncing through a remote of the user's own (private, on GitHub, GitLab,
their own server…). Every device linked to the same remote then has the same practice history.

Git can't live inside an iCloud Drive or Dropbox folder: the service syncs the repository's own
files (`.git`) behind git's back and can damage them. A journal kept with git stays outside those
folders, and git does the syncing.

### Commits

- **Each commit adds one record:** a run file, or an event file together with any score it brings
  in. The first commit adds `clefwise.json` and `.gitattributes`.
- **The message's first line** says what happened, for people reading `git log`. For example:
  `Practice · 5 min · 312 of 320 right · treble`, or `Add piece: <title>`.
- **Author:** `Clefwise`, with the email `<device id>@devices.clefwise.invalid`. The `.invalid`
  domain can't belong to anyone, so no commit carries the user's real address.
- **Author date:** when the run ended, or when the event happened.
- **Commits aren't signed.**
- **A journal that becomes a repository** has its files committed one record at a time, in time
  order, each with its own author date, so `git log` starts with the first run.

### Syncing

With no remote, there is nothing to do. With one, the app syncs after every commit, at launch, and
when the network comes back:

1. Fetch the remote branch (`main`).
2. Check that the remote has `clefwise.json`. If it has no commits yet, push and stop. A remote
   with commits but no `clefwise.json` is refused, so a wrong link can't fill someone's code
   repository with practice files.
3. Re-create each local commit the remote lacks on top of the remote's latest commit, keeping its
   message and author date. Each commit only adds paths:
   - **Path missing on the remote:** add it.
   - **Path there with the same bytes:** skip it. This happens with the root files, or with a score
     added on two devices.
   - **Path there with different bytes:** something has gone wrong: a bug, a damaged disk, or a
     file edited by hand. Nothing the user needs to do, and nothing is lost:
     - *A score:* the right copy is the one whose SHA-256 matches its name. If that's the
       remote's, take it. If it's this device's, the remote's is damaged, so add a commit that
       puts the right bytes back. That's the one change to a file in the journal the format
       allows.
     - *Any other file:* take the remote's copy, since the other devices already have it. Move
       this device's copy to a folder outside the journal, named with the date, and keep it.
     - Either way, carry on syncing, and tell the user once what happened and where the kept copy
       is. A commit left with nothing to add is dropped.
4. Push. If someone pushed in the meantime, go back to step 1. Never force-push.

The history therefore stays a single line, with no merge commits. Linking a device that already has
practice to a remote that also has practice is the same procedure, so the two histories join.

**Access:** we recommend one SSH key per device, made by the app and added to that repository as a
deploy key with write access. The key then reaches only that repository, and a lost device costs
one key. An HTTPS token is the alternative.

## Later

- **Encryption,** as in `pass`: each file's contents encrypted, compressed first, because git
  shrinks run files about five times and encrypted bytes don't shrink. The layout and names stay as
  they are, so names still show when practice happened, not what it was. `clefwise.json` can't
  announce it, since it never changes, so encrypted files will get their own extension.
- **Undoing a `runExcluded`,** with a new event type when it's needed.

## Sizes, measured on a week of real practice

- **A run file:** about 1.2 KB per answer, so a 1,000-note run is about 1.2 MB. The median run
  was 33 KB.
- **In git:** 60 runs took 43 ms each to commit and made a `.git` of 1.3 MB with no clean-up.
- **Reading:** 30,000 run files, about ten years at that week's pace, took under 5 seconds to
  read from scratch.
