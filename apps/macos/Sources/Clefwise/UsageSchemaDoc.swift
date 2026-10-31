extension UsageExport {
    /// SCHEMA.md, after a line about the export itself. Kept in code rather than as a resource
    /// because the release app doesn't ship SwiftPM resource bundles. Describe new event fields
    /// here when adding them to UsageEvents.swift.
    static let schema = #"""
        Everything Clefwise recorded while you used it, for analysing your progress. `events/` is
        the complete record; the CSV tables are built from it for convenience and can always be
        rebuilt from it.

        ## Files

        | File | Contents |
        |---|---|
        | `events/usage-YYYY-MM-DD.jsonl` | The raw log, copied unchanged: one file per local calendar day, one event per line. |
        | `answers.csv` | One row per answer, with the question it answered and its round's settings. |
        | `rounds.csv` | One row per round. |
        | `sessions.csv` | One row per app session, launch to quit. |
        | `settings.json` | The settings as saved when exporting. |
        | `note-stats.json` | The per-note history used to bring up notes you struggle with, as saved when exporting. |
        | `best-scores.json` | Best sprint scores, as saved when exporting. |
        | `SCHEMA.md` | This file. |

        ## Conventions

        - **Times** in the log are UTC, ISO 8601 with milliseconds: `2026-10-30T17:02:11.348Z`.
          The CSVs give each time twice: `…Time` columns exactly like the log, and `…LocalTime`
          columns as `YYYY-MM-DD HH:MM:SS.mmm` wall-clock time in the time zone named at the top of
          this file (with daylight saving time as it was on each date). Day files are named by the
          local day in the Mac's time zone when the events were logged.
        - **Durations**: `…Ms` columns and fields are milliseconds, `…Seconds` seconds.
        - **Accidentals**: −1 flat (♭), 0 natural, 1 sharp (♯).
        - **Key signatures** are counted in fifths: sharps positive, flats negative. 0 = C major,
          1 = G major (one sharp), −3 = E♭ major (three flats).
        - **Staff positions**: 0 = the bottom line, each step up one line or space, so 8 is the top
          line, −1 the space just below the staff and −2 the first ledger line below it. In the
          treble clef 0 is E4, in the bass clef G2.
        - **Pitches** use scientific pitch notation: C4 is middle C, MIDI note 60. Names like
          `F♯4`, `B♭3`, `C4` use the characters ♯ (U+266F) and ♭ (U+266D); naturals have no sign.
        - **Pieces**: bars count from 1 at the start of the piece (not the printed bar numbers);
          staff 1 is the upper staff (right hand on the piano), 2 the lower (left hand); onsets are
          in quarter notes from the start of the piece.
        - Ids are UUIDs. Booleans are `true`/`false`.

        ## The event log (`events/`)

        [JSON Lines](https://jsonlines.org): one JSON object per line, UTF-8, LF line ends. Files
        are only ever appended to, so the only damage to expect is a line cut off by a crash or a
        full disk: skip lines that don't parse (the snippets below do). Lines are in the order they
        were written; within a session, `sequence` gives the exact order.

        Each line holds the envelope fields and the event's own fields side by side:

            {"schema":1,"type":"answerGiven","id":"…","time":"2026-10-30T17:02:11.348Z","session":"…","sequence":42,"round":"…","question":"…","correct":true,"responseMs":1820,…}

        | Field | Meaning |
        |---|---|
        | `schema` | Format version, now 1. Raised only when a field changes meaning; new fields can appear at any time. |
        | `type` | The event type, below. |
        | `id` | This event's own id. |
        | `time` | When it happened (UTC). |
        | `session` | One id per app launch. |
        | `sequence` | Order within the session, from 0. |

        Optional fields without a value are left out of the line.

        ### `appLaunched`: the app started

        | Field | Meaning |
        |---|---|
        | `appVersion` | e.g. `0.1.0`. |
        | `build` | Build number. |
        | `osVersion` | macOS version, e.g. `26.5`. |
        | `model` | Mac model identifier, e.g. `Mac15,12`. |
        | `locale` | e.g. `en_GB`. |
        | `timeZone` | e.g. `Europe/Bucharest`. |
        | `screen` | Screen size in points, `{"width":…,"height":…}` (optional). |

        ### `appTerminated`: the app quit

        | Field | Meaning |
        |---|---|
        | `sessionSeconds` | Seconds since launch. |

        ### `appActivity`: Clefwise became the active app, or stopped being it

        | Field | Meaning |
        |---|---|
        | `active` | `true` when it became the active app. The time from `true` to the next `false` is time actually spent in the app. |

        ### `windowResized`

        | Field | Meaning |
        |---|---|
        | `size` | The whole window's size in points, title bar and toolbar included, `{"width":…,"height":…}`. Logged once when the window first appears, then whenever a resize settles (about 1 s after the last change). |

        ### `settingChanged`: one setting changed

        | Field | Meaning |
        |---|---|
        | `setting` | Its key in the saved settings (see Settings below), nested keys dotted: `naming`, `piece.hand`. |
        | `from`, `to` | The old and new value, as saved. |

        ### `roundStarted`

        | Field | Meaning |
        |---|---|
        | `round` | The round's id, shared by its questions, answers and end. |
        | `via` | What started it: `button`, `key` (Return or Space), `playAgain`. |
        | `settings` | All settings at the start of the round, as saved (see Settings). |
        | `keyFifths` | The key signature the round is in, a random key resolved; for a piece, its first note's. |
        | `piece` | When practising a piece (absent otherwise): |
        | `piece.title` | The piece's title. |
        | `piece.path` | Its file. |
        | `piece.part`, `piece.partIndex` | The part's name, and its index (from 0) in the score. |
        | `piece.hand` | `right` (upper staff), `left` (lower staff) or `both`. |
        | `piece.order` | `inOrder` or `shuffled`. |
        | `piece.startBar` | Bar the round starts from. |
        | `piece.oneNotePerChord` | Only the top note of right-hand chords and the bottom note of left-hand ones. |
        | `piece.noteCount` | Notes this round asks. |
        | `piece.measureCount` | Bars in the part. |

        ### `questionShown`: a note appeared

        | Field | Meaning |
        |---|---|
        | `round` | The round's id. |
        | `question` | This question's id, shared by its answer. |
        | `index` | 0-based count of questions shown so far this round. |
        | `clef` | `treble` or `bass`. |
        | `pitch` | The note as played (see Pitch below). |
        | `written` | The note as written; differs from `pitch` under an 8va or 8vb line. |
        | `position` | Staff position of the written note. |
        | `keyFifths` | The key signature. |
        | `printedAccidental` | The sign printed right before the note, −1/0/1 (0 = ♮); absent when none is printed and the key signature applies. In the whole-bar view it's the sign the bar prints: one earlier in the bar carries on, so a note can be sharp with no sign of its own. Shown on its own, a note gets the sign it needs printed on it. |
        | `octaveShift` | Octaves the note is written below how it sounds: 1 under 8va, −1 under 8vb, 0 normally. |
        | `pieceNote` | Where the note is in the piece (pieces only): `measure` (bar), `staff`, `onset` (quarter notes from the start), `chord` (notes struck together on one staff share a chord id), `symbolIndex` (where it's drawn in its bar: its 0-based index among the notes and rests drawn in the bar on all staves, ordered by time, then staff, voice and pitch, rests first; absent when the piece has no bar layout). |
        | `barView` | Pieces only: `true` when the note was asked in the whole-bar view (its whole bar drawn, the note highlighted), `false` when it was shown on its own. Absent for random notes. |
        | `barStaves` | In the whole-bar view, the staves drawn, top to bottom: `[1, 2]` for both staves of a grand staff, `[1]` or `[2]` for one. Absent otherwise. |
        | `pickChance` | The chance this note had of being picked (random and shuffled rounds), 0–1, for studying the adaptive picking. |
        | `naming` | Note names in use: `letters` (C D E), `solfege` (Do Re Mi, fixed: Do = C), `sargam` (Sa Re Ga, Sa = C). |
        | `input` | How answers are given: `buttons`, `piano`, `keyboard` (typing names). |
        | `hintsVisible` | Whether the staff hints were showing. |
        | `keyNamesVisible` | Whether note names were showing on the piano keys. |

        **Pitch** (`pitch`, `written`, and an answer's `pitch`):

        | Field | Meaning |
        |---|---|
        | `name` | e.g. `F♯4`. |
        | `letter` | `C` to `B`. |
        | `accidental` | −1/0/1. |
        | `octave` | Octave in scientific pitch notation. |
        | `midi` | MIDI note number (60 = C4); F♯4 and G♭4 share one. |

        ### `answerGiven`: an answer that counted

        | Field | Meaning |
        |---|---|
        | `round`, `question` | Ids of the round and the question answered. |
        | `responseMs` | From the question appearing to the answer, pauses left out. |
        | `source` | `click` (note buttons clicked), `shortcut` (keyboard shortcuts for the buttons: letters, 1–7), `typing` (typed names), `piano` (piano keys). |
        | `letter`, `accidental` | What was answered: letter and sign. |
        | `name` | Its name in the naming system in use: `F♯`, `Fa♯`, `komal Re`. |
        | `pitch` | The exact key, for piano answers (see Pitch). |
        | `correct` | Whether it was right. |
        | `wrongOctave` | Piano only: the right note in the wrong octave. |
        | `keystrokes` | Every key pressed while the question was up, in order, each with `key`, `ms` (since the question appeared) and `result`: `typed` (kept as part of a name), `rejected` (refused; the box shook), `deleted` (Backspace), `submitted` (Return, or a completed name submitting), `armed` (♯/♭ armed or disarmed on the note buttons; clicks on those buttons appear as keys `click ♯` / `click ♭`), `other` (pressed but not part of answering). |
        | `scoreAfter`, `streakAfter` | Score and current streak after this answer. |
        | `pausedMs` | How long the round was paused while the question was up (absent when it wasn't). |

        ### `inputIgnored`: an answer or keystroke that didn't count

        While the round is paused (`reason` `paused`), during the pause after a miss, a sign with
        no name in the naming system, and so on.

        | Field | Meaning |
        |---|---|
        | `round` | The round, if one was going. |
        | `reason` | Why it didn't count. |
        | `source` | As for answers, when it was one. |
        | `detail` | More about it, when there is more. |

        ### `roundPaused`: the round's clock stopped

        The Pause button or Space, during a round. While it's paused the time stands still, the
        note is hidden and answers don't count.

        | Field | Meaning |
        |---|---|
        | `round`, `question` | The round, and the question on screen if one was. |
        | `via` | `button` (Pause) or `key` (Space). |
        | `activeMs` | Round time so far, earlier pauses left out. |

        ### `roundResumed`: the round carried on

        | Field | Meaning |
        |---|---|
        | `round`, `question` | As in `roundPaused`. |
        | `via` | `button` (Resume) or `key` (Space). |
        | `pausedMs` | How long this pause lasted. |

        A round can also end while paused (Stop, Esc, quitting), with no `roundResumed`.

        ### `roundEnded`

        | Field | Meaning |
        |---|---|
        | `round` | The round's id. |
        | `reason` | `timeUp` (the sprint clock ran out), `stopped` (Stop or Esc), `pieceComplete` (the last note of a piece), `abandoned` (replaced by opening or closing a piece, or starting over), `appQuit` (the app quit mid-round). |
        | `durationMs` | How long the round went on, pauses left out. |
        | `pausedMs` | Time spent paused (absent when the round never was). |
        | `score` | Correct answers. |
        | `attempts` | All answers. |
        | `bestStreak` | Longest run of correct answers. |
        | `averageResponseMs` | Average response time, as in the round summary (absent when there was nothing to average). |
        | `bestScore` | The best sprint score for these settings (sprints on random notes only). |
        | `isNewBest` | This round set a new best score. |
        | `notesToReview` | The notes missed most, as listed in the round summary. |
        | `unansweredQuestion` | The question still on screen when the round ended, if any: `question` id, `shownMs` (how long it was up, pauses left out), `pausedMs` (how long the round was paused meanwhile, if it was) and its `keystrokes` (as in `answerGiven`). |

        ### `pieceOpened`: a MusicXML file was opened

        | Field | Meaning |
        |---|---|
        | `path` | The file. |
        | `title` | The piece's title. |
        | `via` | `menu`, `button`, `drop` (dropped on the window), `openAnother`, `launch` (reopened at launch). |
        | `parts` | Each part's `name`, `notes`, `measures` (bars), `staves`, and `skipped`: notes left out because they can't be shown (other clefs, double sharps, microtones…). |

        ### `pieceOpenFailed`

        | Field | Meaning |
        |---|---|
        | `path`, `via` | As for `pieceOpened`. |
        | `error` | What went wrong. |

        ### `pieceClosed`

        | Field | Meaning |
        |---|---|
        | `path` | The piece that was closed. |

        ### `uiAction`: a button or menu item used

        | Field | Meaning |
        |---|---|
        | `name` | Which one. |
        | `detail` | More about it, when there is more. |

        ### `statsSnapshot`: what the app knew before the usage log existed

        Recorded once, so the log starts from everything the app knew.

        | Field | Meaning |
        |---|---|
        | `reason` | Why it was recorded. |
        | `noteStats` | As in `note-stats.json`. |
        | `bestScores` | As in `best-scores.json`. |

        ### Settings

        The saved settings, as in `roundStarted.settings`, `settingChanged` and `settings.json`.
        Settings saved by older versions can lack newer keys; the app uses the defaults for those.

        | Key | Meaning |
        |---|---|
        | `clefChoice` | `treble`, `bass` or `both`. |
        | `range` | `staff` (on the staff), `oneLedgerLine` or `threeLedgerLines` (above and below). |
        | `mode` | `sprint` (60 seconds) or `practice` (untimed). |
        | `naming` | `letters`, `solfege` or `sargam`. |
        | `answerInput` | `buttons`, `piano` or `keyboard`. |
        | `showHints` | Staff hints shown. |
        | `showKeyNames` | Note names on the piano keys. |
        | `isMuted` | Sound off. |
        | `key` | `{"fixed":{"_0":{"fifths":N}}}` for a fixed key signature, `{"random":{}}` for a new random one each round. |
        | `addsAccidentals` | Now and then print a ♯, ♭ or ♮ in front of a note, on top of the key signature. |
        | `piece` | `part` (index from 0), `hand`, `order`, `startBar`, `oneNotePerChord`, as in `roundStarted.piece`; and `showsWholeBar`, the "Show the whole bar" checkbox (true unless switched off). |
        | `piecePath` | The last piece opened, reopened at launch. |

        ### `note-stats.json` and `best-scores.json`

        Note stats are keyed by clef and pitch (`treble.F♯4`): `attempts`, `correct`, and
        `recent`, the latest results (up to 8, oldest first, `true` = correct). Best scores are
        keyed by the sprint's setup: `clefChoice.range`, then `.piano` or `.keyboard` unless
        answering with buttons, `.keyN` or `.keyRandom` unless in C major, and `.acc` with added
        accidentals, e.g. `treble.staff` or `both.oneLedgerLine.piano.key-2.acc`.

        ## The tables

        RFC 4180 CSV: a header row, commas between fields, CRLF line ends, and fields holding a
        comma, a double quote or a line break wrapped in double quotes, with quotes doubled. UTF-8
        without a byte-order mark: if a spreadsheet shows ♯ and ♭ garbled, import the file as
        UTF-8 (in Excel, Data → From Text/CSV). An empty cell means no value. Rows are in the order
        the events were logged.

        ### `answers.csv`: one row per `answerGiven`

        | Column | Meaning |
        |---|---|
        | `localTime`, `time` | When the answer was given. |
        | `session`, `round`, `question` | Ids, as in the log. |
        | `questionIndex` | 0-based position of the question in its round. |
        | `clef` | `treble` or `bass`. |
        | `pitch`, `pitchMidi` | The note as played: name and MIDI number. |
        | `written` | The note as written (differs under 8va/8vb). |
        | `position` | Staff position of the written note. |
        | `keyFifths` | The key signature. |
        | `printedAccidental` | −1/0/1; empty when no sign was printed. |
        | `octaveShift` | 1 under 8va, −1 under 8vb, 0 normally. |
        | `pieceBar`, `pieceStaff` | Where the note is in the piece; empty for random notes. |
        | `barView` | Pieces only: `true` when asked in the whole-bar view, `false` when shown on its own; empty for random notes. |
        | `barStaves` | In the whole-bar view, the staves drawn, space-separated: `1 2` for a grand staff, `1` or `2` for one. |
        | `naming`, `input` | The naming system and answer input in use. |
        | `source` | How the answer was given: `click`, `shortcut`, `typing`, `piano`. |
        | `answerLetter`, `answerAccidental`, `answerName` | What was answered. |
        | `answerPitch`, `answerMidi` | The key played, for piano answers. |
        | `correct` | Whether it was right. |
        | `wrongOctave` | Piano only: the right note in the wrong octave. |
        | `responseMs` | From the question appearing to the answer, pauses left out. |
        | `pausedMs` | How long the round was paused while the question was up; empty when it wasn't. |
        | `keystrokes` | How many keys were pressed while the question was up (the keys themselves are in the log). |
        | `rejectedKeystrokes` | How many of those were refused. |
        | `scoreAfter`, `streakAfter` | Score and streak after the answer. |
        | `hintsVisible`, `keyNamesVisible` | Whether the staff hints and the names on the piano keys were showing. |
        | `pickChance` | The chance the note had of being picked (random and shuffled rounds). |
        | `mode`, `clefChoice`, `range`, `addsAccidentals` | The round's settings. |
        | `keySetting` | The round's key setting: a fixed key in fifths, or `random`. |
        | `pieceTitle` | The piece, for piece rounds. |

        The question's columns are empty if its `questionShown` line is missing from the log, and
        the round's if its `roundStarted` is.

        ### `rounds.csv`: one row per round

        | Column | Meaning |
        |---|---|
        | `startLocalTime`, `startTime` | When the round started. |
        | `endLocalTime`, `endTime` | When it ended; empty if no `roundEnded` was logged (the app crashed, or the round is still going). |
        | `session`, `round` | Ids, as in the log. |
        | `via` | What started it. |
        | `mode`, `clefChoice`, `range`, `addsAccidentals`, `naming`, `answerInput` | Settings at the start. |
        | `keySetting` | The key setting: a fixed key in fifths, or `random`. |
        | `keyFifths` | The key the round was in (a random key resolved). |
        | `pieceTitle`, `piecePart`, `pieceHand`, `pieceOrder`, `pieceStartBar`, `pieceOneNotePerChord`, `pieceNotes` | Piece rounds only: as in `roundStarted.piece` (`pieceNotes` is `noteCount`). |
        | `endReason`, `durationMs`, `pausedMs`, `score`, `attempts`, `bestStreak`, `averageResponseMs`, `bestScore`, `isNewBest` | From `roundEnded`. |
        | `accuracy` | `score / attempts`, 0–1. |
        | `notesToReview` | Space-separated. |
        | `answers` | `answerGiven` events logged for the round; equals `attempts` unless lines are missing. |

        ### `sessions.csv`: one row per app session

        | Column | Meaning |
        |---|---|
        | `launchLocalTime`, `launchTime` | When the app started (its first event, if the launch wasn't logged). |
        | `quitLocalTime`, `quitTime` | When it quit; empty if it didn't quit normally (a crash, a forced quit) or is still running. |
        | `session` | Id, as in the log. |
        | `durationSeconds` | Launch to quit, as the app measured it; without a quit, up to the session's last event. |
        | `foregroundSeconds` | Time Clefwise was the active app: from each `appActivity` `true` to the next `false`, or to the session's end. A first `false` counts from launch. Empty when the session logged no `appActivity`. |
        | `appVersion`, `build`, `osVersion`, `model`, `locale`, `timeZone` | From `appLaunched`. |
        | `events` | Events logged. |
        | `rounds` | Rounds started. |
        | `answers`, `correct`, `accuracy` | Answers given, how many were right, and the share right (0–1). |

        ## Loading the data

        Python with pandas:

        ```python
        import glob, json
        import pandas as pd

        answers = pd.read_csv("answers.csv", parse_dates=["time"])
        answers.groupby("clef")["correct"].mean()
        answers.groupby(answers["time"].dt.date)["responseMs"].median()

        # Every event, skipping any line cut off by a crash:
        rows = []
        for path in sorted(glob.glob("events/*.jsonl")):
            with open(path, encoding="utf-8") as file:
                for line in file:
                    try:
                        rows.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
        events = pd.DataFrame(rows)
        events["time"] = pd.to_datetime(events["time"])
        ```

        DuckDB:

        ```sql
        -- Every event, one column per field (NULL where an event type doesn't have it):
        CREATE TABLE events AS
        SELECT * FROM read_json_auto('events/*.jsonl', format = 'newline_delimited',
                                     union_by_name = true, sample_size = -1, ignore_errors = true);
        SELECT type, count(*) FROM events GROUP BY type;

        SELECT clef, avg(correct::INT) AS accuracy, median(responseMs) AS medianMs
        FROM read_csv_auto('answers.csv') GROUP BY clef;
        ```

        jq (`fromjson?` skips lines that don't parse):

        ```sh
        jq -cR 'fromjson? | select(.type == "answerGiven") | {time, correct, responseMs, source}' events/*.jsonl
        jq -nR '[inputs | fromjson? | .type] | group_by(.) | map({type: .[0], count: length})' events/*.jsonl
        ```

        """#
}
