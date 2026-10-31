# Clefwise

Learn to read sheet music. A note appears on the staff, or a whole bar of a real piece with one
note highlighted, and you name it: by clicking its name, playing it on a piano keyboard, or typing
it. Notes can be named with letters (C D E), fixed solfège (Do Re Mi) or sargam (Sa Re Ga). Practise
random notes in any key, or the notes of your own MusicXML scores, and follow your progress over
time.

## Versions

| Folder | Version | Status |
|---|---|---|
| [`apps/macos`](apps/macos) | Native macOS app (Swift, SwiftUI) | Working |

Other versions are welcome, for example a Linux app, a web app or a terminal app. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

```
apps/            one folder per version of Clefwise, each building and testing on its own
  macos/         the macOS app (a Swift package)
spec/            what every version shares, whatever its language
  fixtures/
    scores/      MusicXML test scores (original or public domain)
```

Code shared between versions will go in `core/<language>/` once two versions need the same logic
in the same language. There's none yet.

## Quick start on a Mac

```sh
cd apps/macos
./build-app.sh --open
```

More in [apps/macos/README.md](apps/macos/README.md).

## Licence

[GPL-3.0](LICENSE). Music is drawn with [Bravura](https://github.com/steinbergmedia/bravura),
© Steinberg Media Technologies GmbH, under the SIL Open Font License 1.1; it ships unmodified in
`apps/macos/Resources/Fonts`, with its licence.
