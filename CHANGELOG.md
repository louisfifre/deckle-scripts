# Changelog

All notable changes to deckle-scripts are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/).

This file is generated from the Conventional Commits history by `scripts/git/changelog.ps1`; do not edit it by hand.

## [0.1.2] — 2026-10-30

### Fixed

- **terminal-interaction:** Indent Action Row labels two cells past their Section

## [0.1.0] — 2026-10-30

### Added

- **core:** Read the repository version from annotated tags
- **launcher:** Run discovered scripts in-process, with Logs and a 5.1 entry
- **check:** Move the compliance check to scripts/check-scripts.ps1
- **setup:** Add the setup pack
- **git:** Add the git pack
- **maintenance:** Add the maintenance and dotnet packs
- **update:** Add install and update
- **terminal-interaction:** Seat independent Actions in the label column and open the Header with a logo
- **launcher:** Draw the Deckle Scripts logo and name the repository in the Banner

### Changed

- **core:** Drop the product name from function names
- **core:** Namespace types and tags under DeckleScripts
- **core:** Make the preview the repository menu
- **core:** Make parameters check their object types
- **terminal-interaction:** Run an Execute decision and keep the sample views as a test fixture
- **git:** Drop the Versions section from the git pack
- **git:** Give Release and Changelog their own sections

### Fixed

- **lib:** Keep numeric zeros in action summaries
- **terminal-interaction:** Part independent Actions from an Action Row with a blank line
