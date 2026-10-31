# Test scores

Small MusicXML files that every version's tests read. All of them are original, hand-written
music or not music at all. Never add copyrighted scores.

| File | What it covers |
|---|---|
| `accidentals.musicxml` | "Accidental Study": signs printed, carried and cancelled within a bar; a key change midway; double sharps and microtones, which can't be shown |
| `bar-signs.musicxml` | "Sign Study": almost no `<accidental>` elements, so the bar's signs come from the rule: held until the bar line, per octave and staff, courtesy signs, ties, 8va, two voices |
| `bar-values.musicxml` | "Value Study": note values without `<type>`, dots, a triplet, stems, whole-bar rests, a named voice, placed rests; a grace note, a hidden rest and a double sharp that aren't drawn |
| `bar-view.musicxml` | "Lantern at Dusk": a two-hand piano piece in E minor covering the whole-bar view. It has a pickup, arpeggios, ties, rests, chords, two voices, an 8va line, a clef change, a triplet and sixteenths |
| `broken.mxl` | A damaged compressed file, which must be refused |
| `clarinet-tune.musicxml` | "Clarinet Tune": one staff, written the way MuseScore exports (DOCTYPE, credits) |
| `clarinet-tune.mxl` | The same tune compressed, with a `container.xml` pointing to `Scores/Clarinet Tune.musicxml` and a decoy XML file |
| `clefs.musicxml` | Clefs that can't be shown (C clefs, octave clefs): their notes are skipped and counted |
| `drums-only.musicxml` | Unpitched percussion only: nothing to practise, so it's refused |
| `grand-staff.musicxml` | "Grand Staff Study": a piano part, read lower staff first and low to high; chords per staff; clef changes on the lower staff |
| `no-container.mxl` | `accidentals.musicxml` compressed without a `container.xml` |
| `ottava.musicxml` | 8va and 8vb lines: notes are written an octave away from how they sound |
| `plain-text.musicxml` | Not XML, despite its name: refused |
| `shopping-list.xml` | XML that isn't MusicXML: refused |
| `ties-rests-grace.musicxml` | A pickup bar, ties (including over two bar lines), rests, grace and cue notes |
| `timewise.musicxml` | Timewise MusicXML, which isn't supported: refused with an explanation |
| `truncated.musicxml` | A file cut off partway: refused as damaged |
| `voice-and-piano.musicxml` | "Evening Song": a voice and a piano part, each with its own key and clefs; bar rests in every part; parts with nothing to read are dropped |
| `zipped-score.xml` | A compressed score named `.xml`, recognised by its content (`accidentals.musicxml` inside) |
