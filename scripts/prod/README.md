---
name: Prod
description: Deploy a version origin holds to the prod copy, roll it back, and see where every project's prod stands.
order: 300
---

# Prod

The prod copy of a repository is the build its maintainer runs every day. This
pack puts a version there the same way in every repository, and keeps one
contract:

1. Prod comes from a version tag on origin, never from a working tree.
2. It is built in a frozen snapshot of that commit, outside every checkout
   someone edits.
3. A check passes before anything is put in place; if it fails, prod stays as
   it was.
4. What runs is never stopped: a new build waits for the next start.
5. A rollback is one command.
6. Prod says which version it runs.

## Scripts

- `deploy-prod.ps1` deploys (Update prod), rolls back (`-Rollback`) or reports
  (`-Status`). `-Ref` picks a tag, branch or commit origin holds; the default
  is the highest `vX.Y.Z` tag on origin. `-Force` stages a version again.
- `prod-status.ps1` walks the repositories beside this one (the folder that
  holds the primary checkout, or `-Path`) and reports, for each with prod
  settings: the version running, the version staged, and how many commits the
  running build is behind origin's branch. `-NoFetch` reads origin as last
  fetched.
- `prod-start.ps1` is the start wrapper; it is not run from here (below).
- `prod-common.ps1` holds the steps the scripts share.

## The settings

Each repository writes `scripts/prod.settings.psd1`, beside the pack rather
than in it, so an update never meets it. It is read with
`Import-PowerShellDataFile`, which runs no code. It is read from the checkout
that runs the deploy, the primary one after a merge into main.

```powershell
@{
    # Run in the snapshot by pwsh -Command; optional.
    Build  = 'dotnet build src/App/App.csproj -c Release'
    # Run after the build; a non-zero exit stops the deploy. Required.
    Check  = 'pwsh -NoProfile -File scripts/self-check.ps1 -Target $env:PROD_SNAPSHOT'
    # The folder of the snapshot that becomes the prod copy; '.' for all of it.
    Output = 'artifacts/bin/App/release'
    # The program start.ps1 starts, relative to the slot: an .exe or a .ps1.
    Start  = 'App.exe'
    StartArguments = @()
    # 'start' (default): start.ps1 swaps the slots. 'app': the app does it.
    Swap   = 'start'
    # Folders of current\ that belong to the machine (logs, data) and follow
    # the build that runs at each swap.
    Carry  = @()
    # Defaults: prod\ in the primary checkout, the lag read against main, and
    # the snapshot kept between deploys for its build caches.
    Root   = 'prod'
    Branch = 'main'
    Clean  = $false
}
```

`Build` and `Check` run with the snapshot as working directory and these
variables: `PROD_SNAPSHOT` (the snapshot), `PROD_OUTPUT` (the Output folder
in it), `PROD_COMMIT`, `PROD_VERSION` and `PROD_PRIMARY` (the primary
checkout). Add `prod/` to the repository's `.gitignore`.

## The prod copy

```
<Root>\current\        the build that runs
<Root>\next\           a complete build waiting for the next start
<Root>\previous\       the build current\ replaced, kept for a rollback
<Root>\next.staging\   a build being written; nothing starts from it
<Root>\start.ps1       the start wrapper, with Swap 'start'
<Root>\start.log       what each start swapped, or why it did not
```

Each slot carries `.prod.json`: its version, commit, ref, deploy time and how
it starts. The stamp moves with its folder, so whoever swaps the slots carries
it along.

A deploy:

1. fetches origin and resolves the ref there, so a local `main` ahead of
   origin or a tag never pushed is refused;
2. checks the commit out in `<worktrees>\<repo>\prod-build`, a detached
   worktree reserved to the deploy (`C:\Code\projects\app` gives
   `C:\Code\worktrees\app\prod-build`); its untracked build caches stay between
   deploys unless `Clean` is set;
3. runs `Build`, then `Check`;
4. copies `Output` to `next.staging\`, writes the stamp, then renames it to
   `next\`; a start never sees half a build;
5. on the first deploy, with `current\` absent or empty, renames it to
   `current\` instead. A `current\` that holds anything, stamped or not, is a
   build that may run: it is never overwritten;
6. with Swap `start`, refreshes `<Root>\start.ps1`.

One deploy writes a prod copy at a time (`deploy.lock`). A failure at any step
removes `next.staging\` and leaves the rest as it was. A version already
staged, or running with nothing staged, is skipped.

A rollback renames `previous\` to `next\`; the next start runs it.

## The swap at the next start

With Swap `start`, the person starts prod through the wrapper, from a shortcut
for instance:

```powershell
pwsh -NoProfile -File <Root>\start.ps1 [arguments for the app]
```

When `next\` holds a stamped build and no process runs from `current\` (its
program sits in `current\`, or its command line names it), the wrapper moves
the `Carry` folders into `next\`, renames `current\` to `previous\` and
`next\` to `current\`. A swap that fails puts back what moved. Then it starts
the stamp's `Start` program with its `StartArguments`, then its own
arguments. While a program runs from `current\`, it starts `current\` as it is
and `next\` keeps waiting.

An app that swaps the slots itself, at its own start, sets Swap `app`: the
deploy writes no wrapper, and the app reads the same layout and stamps.
