# Rubric: "How does CoffeeMud parse and dispatch a player command end-to-end?"

Ground truth derived from the KoffeeMud CBM graph, 2026-06-03. Score = facts
present / total. Deduct for any hallucinated class/method not in the codebase.

Core facts (1 point each):

- [ ] **Input read**: a **`Session`** (`com/planet_ink/coffee_mud/Common/interfaces/Session.java`,
  impl `S_StdSession`) reads the raw input line from the player's connection.
- [ ] **Lookup**: the command library **`CMLib.commands()`** maps the first input word to a
  **`Command`** by matching against `Command.getAccessWords()` (the trigger words); it also
  resolves Socials and Abilities. Unknown input ⇒ `handleUnknownCommand(...)`.
- [ ] **Enqueue**: the parsed command is queued on the MOB via
  `mob.enqueCommand(cmds, metaFlags, actionCost)` — a speed/action-cost queue, not run inline.
- [ ] **Consume on tick**: `StdMOB.tick()` → `dequeCommand()` → **`doCommand(Object O,
  List<String> commands, int metaFlags)`** pulls the queued command when action points allow.
- [ ] **Type dispatch** in `doCommand`: `Command` ⇒ `((Command)O).execute(this, cmds, metaFlags)`;
  `Social` ⇒ `invoke(...)`; `Ability` ⇒ `CMLib.english().invokeSkill(...)`; else
  `CMLib.commands().handleUnknownCommand(...)`.
- [ ] **Execute**: **`Command.execute(MOB, List<String>, int)`** (interface
  `Commands/interfaces/Command.java`) runs the command; involves `securityCheck()`,
  `preExecute()` / `executeInternal()`, and sends output back to the player's session.

Bonus (0.5 each, not required):

- [ ] Ties the queue to the tick/action-cost system (commands consume action points per tick).
- [ ] `MUD.executeCommand` / `MudHost.executeCommand` as a host-level command entry.
- [ ] `metaFlags` semantics (e.g. MUDCMD/forced/order) affecting execution.

Grading note: caveman/terse phrasing is NOT penalized. Score technical facts only.
