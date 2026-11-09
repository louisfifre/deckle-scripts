# Deckle Scripts

A terminal menu that offers the scripts of a repository, with the packs of
scripts a repository needs from its first day: setup, versions and
maintenance. It runs under PowerShell 7 on Windows and installs into
any git repository as a vendored `scripts/` folder, updated from this repository.

## Install

You need Git and PowerShell 7. In the repository to equip:

```powershell
irm https://raw.githubusercontent.com/louisfifre/deckle-scripts/main/install.ps1 | iex
.\scripts\setup\install-hooks.ps1 -Apply   # once: TREE.md and scripts/INVENTORY.md at each commit
```

The first line copies the latest version tagged on GitHub into `scripts/`:
the menu, its library and the `git`, `maintenance` and `setup` packs. The
list of installed files goes to `scripts/.deckle-scripts/manifest.json`.

A version that only exists in a local clone (not pushed yet) installs from
the clone's own update script, pointed at the repository:

```powershell
pwsh -File C:\Code\deckle-scripts\scripts\settings\update.ps1 -Target . -Source C:\Code\deckle-scripts -Apply
```

## Update

In the equipped repository:

```powershell
.\scripts\settings\update.ps1          # preview: the version and the files that would change
.\scripts\settings\update.ps1 -Apply   # install it
```

The source is the one recorded at the last install. Add
`-Source C:\Code\deckle-scripts` to take a local clone, and
`-Version X.Y.Z` to pick a version rather than the latest tag. An installed
file edited by hand stops the update: make the change here, tag it, update
again. Then commit the `scripts/` changes of the equipped repository. The
menu offers both commands under Settings.

## Use

```powershell
.\scripts\menu.ps1
```

The menu discovers every script under `scripts/` that carries a Header, and
offers the folders as levels. Its Settings level holds the launcher's own
scripts: `scripts/settings/update.ps1` checks for and applies the next
version; `scripts/settings/check-scripts.ps1` reports the scripts the menu
would hide and the conventions they break.

## For a shell or an agent

```powershell
.\scripts\menu.ps1 -List                 # every Action: id, label, script, arguments, variant
.\scripts\menu.ps1 -Run <id> [-Variant v] # one Action, its Journal, an exit code
.\scripts\menu.ps1 -Snapshot Menu        # one deterministic frame, for inspection
```

`scripts/INVENTORY.md`, regenerated at each commit, lists every script with
its sentence, actions and parameters, those the menu hides included: an
agent reads it to pick a script instead of opening each one.

## Writing a script the menu offers

A script is offered once it carries a comment-based Header: `.SYNOPSIS` is
its label, `.DESCRIPTION` its sentence, `.NOTES` holds `section`, `order`
and the `action:` lines (`Label | arguments | danger | Confirmation
sentence.`); a label written `Row / cell` makes the Action one cell of a
row the scripts of its folder share. A single `[ValidateSet]` string
parameter becomes its Variants, and such a script fills its own rows.
A folder is a level, labelled by the front matter of its
`README.md`. A script without a Header stays hidden by choice.

## This repository

- `scripts/lib/` holds the launcher and the shared library.
- `scripts/tests/` holds the tests: each `*.tests.ps1` runs alone with
  `pwsh -NoProfile -File` and prints `PASS`.
- `TERMINAL-INTERACTION-SPEC.md` and `GLOSSARY.md` name the concepts of the
  menu.
- The version is the highest annotated `vX.Y.Z` tag; `scripts/git/record-version.ps1`
  records the next one, `scripts/git/mark-release.ps1` marks it published.

## License

MIT. See [LICENSE](LICENSE).
