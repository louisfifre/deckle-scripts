# Launcher bug notes

## Every Action failed with Invoke-LauncherExecution not recognized

- **Trigger:** Activate any Action of the menu opened through `scripts/menu.ps1`, from VS Code's build task or from a terminal.
- **Observed symptom:** The run stopped at once with « The term 'Invoke-LauncherExecution' is not recognized as a name of a cmdlet ».
- **Cause:** The Execute decision's runner is built with `GetNewClosure()`, which binds it to a new dynamic module that sees only the global scope. `menu.ps1` calls `launcher.ps1` with `&`, so the launcher's dot-sourced functions live in a script scope below the global one, out of the runner's sight. The tests ran under `pwsh -File`, whose script scope is the global one, so they never saw it.
- **Violated invariant:** An Action runs the same whether the launcher is entered through `menu.ps1` or loaded at the global scope.
- **Recurrence cue:** A scriptblock built with `GetNewClosure()` calls a function by name that is neither global nor exported, or a test loads the launcher at its own top level instead of below it.

Regression coverage: `scripts/tests/launcher/runner-scope.tests.ps1` loads the launcher in a child scope, as `menu.ps1` does, and runs an Action through the Execute decision's runner.
