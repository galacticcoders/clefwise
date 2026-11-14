# Test scores

Small MusicXML files that every version's tests read. All of them are original, hand-written
music or not music at all. Never add copyrighted scores.

| File | What it covers |
|---|---|
| `accidentals.musicxml` | "Accidental Study": signs printed, carried and cancelled within a bar; a key change midway; double sharps and microtones, which can't be shown |
| `auto-beams.musicxml` | "Paper Boats": no beams written anywhere, so notes are beamed by the beat. A 6/8 pickup counted back from its end, eighths in threes, 2/4 sixteenths in fours, an eighth and two sixteenths, rests and a quarter across the beat breaking groups, a lone eighth, hooks, chords, a triplet, and cut time beamed in fours |
| `bar-signs.musicxml` | "Sign Study": almost no `<accidental>` elements, so the bar's signs come from the rule: held until the bar line, per octave and staff, courtesy signs, ties, 8va, two voices |
| `bar-values.musicxml` | "Value Study": note values without `<type>`, dots, a triplet, stems, whole-bar rests, a named voice, placed rests; a grace note, a hidden rest and a double sharp that aren't drawn |
| `bar-view.musicxml` | "Lantern at Dusk": a two-hand piano piece in E minor covering the whole-bar view. It has a pickup, arpeggios, ties, rests, chords, two voices, an 8va line, a clef change, a triplet and sixteenths |
| `beams.musicxml` | "Beam Study": a piano piece with `<beam>` and `<stem>` written the way MuseScore exports them. Common time, then 3/4. Bar 1 is the user's reference rhythm: an eighth rest, then 16 16 8 16 16 under one beam with a second beam over each pair of sixteenths. Then sixteenths beamed with an eighth, hooks either way, 32nds with three beams, chords with the beam on their first note only, a second voice with stems down, a tied-over note inside a group, and two broken groups (a begin with no end, an end with no begin) that must be drawn with flags |
| `broken.mxl` | A damaged compressed file, which must be refused |
| `clarinet-tune.musicxml` | "Clarinet Tune": one staff, written the way MuseScore exports (DOCTYPE, credits) |
| `clarinet-tune.mxl` | The same tune compressed, with a `container.xml` pointing to `Scores/Clarinet Tune.musicxml` and a decoy XML file |
| `clefs.musicxml` | A clef change in every bar: alto, which can't be shown (its notes are skipped and counted), treble, a treble with an 8 below (the guitar clef), then bass |
| `drums-only.musicxml` | Unpitched percussion only: nothing to practise, so it's refused |
| `grand-staff.musicxml` | "Grand Staff Study": a piano part, read lower staff first and low to high; chords per staff; clef changes on the lower staff |
| `guitar-drop-d.musicxml` | "Lowered String": guitar in drop D as MuseScore 4 exports its classical guitar, the treble clef with an 8 below (`clef-octave-change` -1) and every pitch as it sounds; "6=D" written as text in bar 1; a melody with stems up over a bass with stems down that reaches the open 6th string (D2); beams and a chord |
| `guitar-tab.musicxml` | "Tab Study": a guitar with a linked tablature staff, as MuseScore 4 exports it: one part with two staves, notes in the guitar clef and a TAB staff in drop D (`staff-tuning`) repeating them with their strings and frets |
| `guitar-transpose.musicxml` | "Open String Scale": guitar written in a plain treble clef with `<transpose>` an octave down (pitches as written, an octave above how they sound); a scale from the open low E, beams, a placed rest |
| `no-container.mxl` | `accidentals.musicxml` compressed without a `container.xml` |
| `ottava.musicxml` | 8va and 8vb lines: notes are written an octave away from how they sound |
| `plain-text.musicxml` | Not XML, despite its name: refused |
| `shopping-list.xml` | XML that isn't MusicXML: refused |
| `ties-rests-grace.musicxml` | A pickup bar, ties (including over two bar lines), rests, grace and cue notes |
| `timewise.musicxml` | Timewise MusicXML, which isn't supported: refused with an explanation |
| `truncated.musicxml` | A file cut off partway: refused as damaged |
| `voice-and-piano.musicxml` | "Evening Song": a voice and a piano part, each with its own key and clefs; bar rests in every part; parts with nothing to read are dropped |
| `zipped-score.xml` | A compressed score named `.xml`, recognised by its content (`accidentals.musicxml` inside) |
