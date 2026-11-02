# Terminal-interaction bug notes

## Every Action failed with Get-TerminalStateFrame not recognized

- **Trigger:** Activate any Action of the launcher, from VS Code's build task or from a plain terminal.
- **Observed symptom:** The run stopped at once with « The term 'Get-TerminalStateFrame' is not recognized as a name of a cmdlet ».
- **Cause:** `Invoke-TerminalExecution` built its paint callback with `GetNewClosure()`. A closure is bound to a new dynamic module, which sees the global scope but not the private functions of the module that built it. The same binding kept the `$lastFrame` assignment inside the closure, so each repaint compared against the frame painted before the run instead of the one on screen.
- **Violated invariant:** A callback the module hands to a caller works from the caller's scope, and each repaint compares against the frame left on screen.
- **Recurrence cue:** A scriptblock built with `GetNewClosure()` inside a module calls a function the module does not export, or assigns a variable it expects the enclosing function to read.

Regression coverage: `scripts/tests/terminal-interaction/interaction.tests.ps1` runs an Execute decision whose Runner paints from outside the module, and checks that every paint compares against the frame painted just before it.
