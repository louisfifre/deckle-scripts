# Deckle Scripts

A terminal menu that offers the scripts of a repository, with the packs of
scripts a repository needs from its first day: setup, versions and
maintenance. A pack is a folder of scripts under `scripts/` that installs as
a unit. It runs under PowerShell 7 on Windows and installs into any git
repository as a copy kept in its `scripts/` folder, updated from this
repository.

## Install

You need Git and PowerShell 7 (`winget install Microsoft.PowerShell`). In the
repository to equip:

```powershell
irm https://raw.githubusercontent.com/louisfifre/deckle-scripts/main/install.ps1 | iex
.\scripts\setup\install-hooks.ps1 -Apply
```

The first line copies the latest version tagged on GitHub into `scripts/`:
the menu, its library and the `git`, `maintenance` and `setup` packs. The
list of installed files goes to `scripts/.deckle-scripts/manifest.json`. The
second installs the git hooks that regenerate `TREE.md` and
`scripts/INVENTORY.md` at each commit; hooks are not versioned, so run it
again in every fresh clone. It refuses when `core.hooksPath` is set.

To install from a local clone instead, for a version not pushed yet, run the
clone's own update script and point it at the repository:

```powershell
pwsh -File C:\Code\deckle-scripts\scripts\settings\update.ps1 -Target . -Source C:\Code\deckle-scripts -Version X.Y.Z -Apply
```

Without `-Version`, a local clone is read as it is on disk, uncommitted
changes included: that is for trying a change before tagging it.

## Update

In the equipped repository:

```powershell
.\scripts\settings\update.ps1          # preview: the version and the files that would change
.\scripts\settings\update.ps1 -Apply   # install it
```

The update reads the source recorded at the last install: the GitHub URL, or
the clone's path if the last install came from a local clone. `-Source`
changes it (a URL or a path), `-Version X.Y.Z` picks a version rather than
the latest tag. Then commit the `scripts/` changes of the equipped
repository. The menu offers both commands under Settings.

Two cases stop an update. An installed file edited by hand: make the change
in this repository, tag it, update again, or pass `-Force` to drop the local
edit. A file the install does not own sits where the new version puts one
(a repository's own `scripts/menu.ps1`, say): move or rename it, `-Force`
does not override it.

## Use

```powershell
.\scripts\menu.ps1
```

The menu shows the scripts under `scripts/` that carry a Header, the comment
block at the top of a script that names it (see below). Each folder is a
level: an entry ending with `…` opens it, Escape goes back. Settings, at the
bottom, holds the launcher's own scripts: `update.ps1` checks for and applies
the next version from the recorded source; `check-scripts.ps1` reports the
scripts the menu would hide and the conventions they break. Logs lists the output
of every action run since the menu opened.

## For a shell or an agent

```powershell
.\scripts\menu.ps1 -List                  # every action: id, label, script, arguments, variant
.\scripts\menu.ps1 -Run <id> [-Variant v] # one action by the id -List gives (settings.update.0), with an exit code
.\scripts\menu.ps1 -Snapshot Menu         # one deterministic frame, for inspection
```

`scripts/INVENTORY.md`, regenerated at each commit, lists every script with
its sentence, actions and parameters, those the menu hides included: an AI
agent reads it to pick a script instead of opening each one.

## Writing a script the menu offers

A script is offered once it carries a comment-based Header: `.SYNOPSIS` is
its label, `.DESCRIPTION` its sentence, `.NOTES` holds `section`, `order`
and the `action:` lines (`Label | arguments | danger | Confirmation
sentence.`); a label written `Row / cell` makes the action one cell of a
row the scripts of its folder share. A single `[ValidateSet]` string
parameter becomes its Variants, the values the menu asks to choose from, and
such a script fills its own rows. A folder is a level, labelled by the front
matter of its `README.md`. A script without a Header stays hidden by choice.
`GLOSSARY.md` defines the other words of the menu.

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
