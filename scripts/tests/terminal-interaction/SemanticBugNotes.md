# Terminal-interaction semantic bug notes

## Nested Section labels expanded into full headings

- **Trigger:** Render a nested Action Menu whose Sections group independent operations, such as Maintenance statistics, cleanup, and AI-session actions.
- **Observed symptom:** Each Section became an uppercase full-width rule followed by a separate option row, multiplying whitespace and breaking the command-column rhythm.
- **Cause:** The renderer had only one visual projection for a semantic Section: a full heading and separator.
- **Violated invariant:** In a nested Action Menu a Section orders its rows and draws nothing: no heading, no rule, no blank line, and its independent Actions keep their intents.
- **Recurrence cue:** A nested menu emits a `Section` or `SectionSeparator` segment, or a Section label appears in its frame.

Regression coverage: `scripts/tests/terminal-interaction/layout.tests.ps1` verifies that a nested menu draws no heading or rule, that its Sections follow one another without a gap on stable option tracks, and that its Actions keep the `Action` role; `theme.tests.ps1` verifies that role on a nested independent Action.

## Independent Actions were declared as Action Variants

- **Trigger:** Describe a submenu with two independent operations that should appear near each other, such as README pulse and Changelog.
- **Observed symptom:** The catalog declared the Section label as an Action subject and the independent operations as its variants.
- **Cause:** A visual row shape was exposed as the workflow declaration, so sharing a row determined the semantic relationship between targets.
- **Violated invariant:** Sections contain semantic Actions, Accesses, and Action Rows; Action Variants are only alternate values of one shared Action, and a row that several Actions share is declared in their Headers as a named row whose cells keep their own intents.
- **Recurrence cue:** A caller declares independent operations as the `[ValidateSet]` values of one Action, or changes object types to obtain a preferred column.

Regression coverage: `scripts/tests/terminal-interaction/contracts.tests.ps1` validates Section items, while `layout.tests.ps1` and `theme.tests.ps1` prove that independent Actions can share responsive layout without becoming Action Variants.

## Filter labels inherited the Action subject color

- **Trigger:** Render a Preparation with named Filters under the default Deckle theme.
- **Observed symptom:** Filter labels such as `Scope`, `Files`, `Measures`, and `Grouping` rendered cyan like Action subjects.
- **Cause:** The Preparation layout projected Filter labels through the `Action` presentation role even though they are non-interactive labels, not Actions.
- **Violated invariant:** Filter labels take the body presentation, while the labels of Action Rows alone use the teal `ActionLabel` color.
- **Recurrence cue:** A Preparation Filter label is emitted with the `Action` or `ActionLabel` presentation role, or resolves to the `ActionLabel` color.

Regression coverage: `scripts/tests/terminal-interaction/preparation.tests.ps1` verifies that a rendered Filter label uses the neutral body presentation while Selector targets retain their adjustment role.
