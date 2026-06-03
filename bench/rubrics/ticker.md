# Rubric: "How is the MUD ticker implemented?"

Ground truth derived from the KoffeeMud CBM graph, 2026-06-03. Score = facts
present / total. Deduct for any hallucinated class/method not in the codebase.

Core facts (1 point each):

- [ ] **`Tickable`** interface (`com/planet_ink/coffee_mud/core/interfaces/Tickable.java`)
  is the unit that gets ticked. `tick(Tickable host, int tickID)` returns a boolean
  (false ⇒ stop ticking this object). Also `getTickStatus()`, `name()`.
- [ ] **`TickClient`** wraps a `Tickable` with a tick-down counter; `tickTicker(...)`
  is what actually invokes the object's `tick()`.
- [ ] **`TickableGroup` / `StdTickGroup`** (`core/threads/`) group `TickClient`s that
  share a tick interval. `StdTickGroup.run()` iterates `tickers()` and calls
  `client.tickTicker(false)`; empty groups remove themselves.
- [ ] **`ServiceEngine`** (`core/threads/ServiceEngine.java`) implements **`ThreadEngine`**
  (reached as `CMLib.threads()`) — the engine that owns the tick groups and schedules
  each group's `run()` on its interval. `startTickDown(...)` registers a Tickable.
- [ ] **Tick interval** comes from `CMProps.TIME_TICK` / `getTickMillis()` (default
  ~4000 ms); `TICKS_PER_RLMIN = 60000 / TIME_TICK`. (Exact ms value = bonus.)
- [ ] **Registration path**: game objects (Abilities, Behaviors, MOBs, Items, Rooms)
  start ticking via `CMLib.threads().startTickDown(tickable, tickID, ticks)`.
- [ ] **Run gating**: ticks only fire when `CMProps.isState(HostState.RUNNING)` and
  not `CMLib.threads().isAllSuspended()`.

Bonus (0.5 each, not required):

- [ ] `getTickStatus()` / `STATUS_*` constants describe what a tickable is doing.
- [ ] `ServiceEngine` health/mishap monitoring (detects stuck/long ticks).
- [ ] `MUD.java` instantiates the `ServiceEngine` (`serviceEngine = new ServiceEngine()`).

Grading note: caveman/terse phrasing is NOT penalized. Score technical facts only.
