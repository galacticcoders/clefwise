# Contributing

Clefwise is meant to grow into several versions without everyone having to use the same language.
Today there's the macOS app; a Linux app, a web app or a terminal app could join it. The layout
keeps versions independent and shares only what has to match.

## Where things go

- **A new version gets its own folder under `apps/`**, such as `apps/web`, `apps/cli` or
  `apps/linux`, in whatever language suits it.
  - Give it a README: how to build, run and test it, and what it supports so far.
  - Keep its build files, dependencies and tooling inside its folder, not at the top level.
  - Its tests should read the shared test scores in `spec/fixtures/scores`.
- **Code shared between versions goes under `core/<language>/`**, such as `core/swift` or
  `core/rust`, but only once two versions want the same logic in the same language. Until then,
  versions don't depend on each other.
- **Anything every version must agree on goes in `spec/`.** For now that's the test scores. Later
  it can hold expected results and written-down rules. See [spec/README.md](spec/README.md).

## Keeping versions consistent

For now the macOS app is the reference. Where `spec/` doesn't describe a behaviour yet, the macOS
code and its tests define it. That covers, for example:
- how answers are checked in each naming system;
- which sharps and flats a bar prints;
- what the MusicXML importer leaves out.

If you implement one of these rules, consider writing it down in `spec/` as you go.

## Test scores

- **Only original or public-domain music.** Never add copyrighted scores, not even for tests.
- **Keep them small,** and list each one in
  [spec/fixtures/scores/README.md](spec/fixtures/scores/README.md) with what it covers.
- **A changed score can break every version's tests.** Run them all, or say so in your pull
  request.

## Working together

- Branch from `main` and open a pull request. Keep each pull request to one version, or to
  `spec/`.
- Keep build output out of git: `.gitignore` covers Swift's, so add your toolchain's.
- The repository is public. Never commit keys, tokens, passwords, personal email addresses or
  machine-specific paths.

## Licence

Clefwise is licensed under GPL-3.0. Contributions are accepted under the same licence.
