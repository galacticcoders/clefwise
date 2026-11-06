# Spec

What every version of Clefwise shares, whatever language it's written in. Nothing here belongs to
one particular app.

## What's here

- [`fixtures/scores/`](fixtures/scores): MusicXML test scores that every version's tests read.
- [`practice-journal.md`](practice-journal.md): the practice journal, the folder of plain files a
  person's practice is kept in (a draft; the macOS app is being built to it).

## What can go here later

Add these when a second version needs them, not before.

- **Expected results for the test scores,** for example as JSON: the notes to ask, each bar's
  notes and rests, and the signs it prints. A new version can then check itself against the macOS
  app's answers.
- **Written-down rules** that only the macOS code and tests define today:
  - note naming in letters, fixed solfège and sargam;
  - answer checking, and what typed answers may look like;
  - key signatures, and which sharps and flats a bar prints;
  - written versus sounding pitch under 8va lines;
  - what the MusicXML importer leaves out.
- **The usage-log format,** so every version writes the same practice history and can read the
  others'. Today it's documented in the macOS app's data export, as `SCHEMA.md`, written from
  `apps/macos/Sources/Clefwise/UsageSchemaDoc.swift`.
