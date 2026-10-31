# Changelog

## 2.3.2-dev2 — Engine Lab

### What to test

- **Engine Lab** — Settings → Engine Lab, or the in-game Learn menu. Pick two
  or more engines, choose a preset (Quick / Standard / Accurate / Custom), and
  run a round robin or a gauntlet. The run has a live board, per-game progress,
  pause/resume/cancel, and a report afterwards with ratings, intervals, ratings
  quality, performance percentiles, a PGN of every game and CSV/JSON exports.
- **Ratings you can argue with.** Ratings are fitted to all games at once
  (Bradley–Terry, not move-by-move Elo), centred on 1500 across the engines in
  the run, and always shown with a 95% interval and a quality grade. A rating
  from eight games is labelled as such instead of being printed next to a
  rating from a thousand.
- **No invented absolute Elo.** Calibrated Elo only appears when you have
  declared a published rating for an engine in the run (with its source, date,
  hardware and time control) *and* the run's move budget matches it within 20%.
  Declare one under Benchmark → Calibration anchors; the form asks for every
  field the check needs and refuses an anchor with a gap. Otherwise the report
  says why there is no absolute number.
- **Games that were not chess are not rated.** A forfeit (engine crashed,
  timed out, illegal move), an aborted game, or a game stopped at the ply cap
  is counted, given a reason and kept out of the fit — it used to be recorded
  as a draw.
- **Stability check** — start an engine repeatedly and search repeatedly, and
  see whether it leaks, hangs or reports nonsense. This is the check that
  would have caught the engines that were not spending the time they were
  given.
- **Benchmarks run themselves, within a budget**: after adding an engine, and
  after an engine's binary changes. Quick preset, at most 24 games and ten
  minutes, and every decision — including a refusal — carries a reason.

### Engines

- Engine results, standings and ratings are keyed by a stable engine id, not by
  the display name. Two profiles called "Stockfish" no longer share a score,
  and a renamed profile keeps its history.
- Each benchmark records the engine's fingerprint (SHA-256 of the binary, or
  size+mtime when hashing is unavailable, marked as the weaker signal), the
  options it advertised, the options actually applied, and the platform and
  backend the engine ran on. Two numbers from different cohorts are never put
  in one rating pool.
- Matches and tournaments now use the same game loop as the Lab: legal-move
  checking, forfeit classification and ply-cap adjudication exist once, and a
  game that ended without a result is reported as such rather than as a draw.


## Unreleased — custom UCI engines, finished

### Engines

- **Custom UCI engines work end to end.** An engine added in the Engine Manager
  now appears in the engine selector, the hint-engine list, multi-engine
  analysis and engine-vs-engine matches, and actually plays the game. Engine
  selection is stored by a stable profile id instead of by display name, so two
  engines with the same name — or a renamed profile — stay distinct.
- **A failing engine is no longer saved as a working one.** `initialize()`
  reported success even when the binary was missing, was not executable, never
  answered `uci`, or died during the handshake. The Engine Manager's error path
  could therefore never run. All four cases now fail with a specific error,
  set the state to `error`, and leave nothing stored.
- **UCI options are discovered and applied reliably**: the option list is
  rebuilt on each handshake (it used to accumulate duplicates), option values
  that the engine no longer advertises no longer break the dropdown, and the
  text fields keep the caret where you put it instead of resetting on every
  rebuild.
- **Evaluation is no longer inverted on Black-to-move positions.** UCI reports
  `score cp`/`score mate` from the side to move; the app draws it from White's.
  Every engine that reports an evaluation now converts: the built-in engine,
  custom UCI, Stockfish (all three builds — process, downloaded/iOS and
  browser), Lynx (native and WASM), Lc0 native, and Frozenight (native FFI and
  WASM). Stockfish and Lynx also report forced mates, which the browser builds
  used to drop entirely.
- **Engine switching** stops the previous engine before disposing it, resets
  the crash-restart budget, and rebuilds the *new* engine after a crash (the
  rebuild closure used to keep pointing at the engine selected at start-up).
- **Matches and tournaments dispose their engines.** Nothing did before, so
  every match left its engine processes running.
- **Multi-engine analysis isolates failures**: one engine that cannot start no
  longer discards the results of the others.
- The hint-engine setting is persisted (it never was) and takes effect
  immediately when changed (the hint engine was built once and then reused).

### Fixed in the review of this change

- Switching engines did not deliver `Hash`, `Threads` or `UCI_Chess960`: the
  options were applied before the new engine had finished starting, and so went
  to the engine that had just been disposed. The switch is now awaited, the new
  selection is only recorded once it actually started, and an engine that fails
  to start is replaced by the previous one with a message saying so.
- An engine id naming an engine that does not exist no longer quietly plays as
  the built-in engine.
- The evaluation keeps the colour of the search it came from. A real engine
  emits a burst of `info` lines while the previous search is being stopped, and
  the colour was read from a field the caller had already overwritten — so the
  eval bar briefly flipped sign whenever a search replaced another.
- Engine profiles saved by an older version (no id) can be removed and edited
  again. Their id was generated afresh on every read, so the delete or update
  matched nothing and silently did nothing; the id is now derived from the entry
  and written back, and every mutation re-reads the store first.
- The Engine Manager's removal confirmation names an auto-detected engine by the
  name it reports instead of by its (empty) user-supplied name.
- The Maia3 (Dart) analysis is no longer shown inverted for Black. Its value
  head is the *mover's* win probability — the board is mirrored into the model
  when Black is to move — and it was reported as White's.
- Two user-added engines with the same name no longer crash the settings screen
  (the hint-engine list is keyed by id, like the engine selector, and a name
  saved by an older version is migrated to one).
- A disposed engine can no longer be brought back to "ready" by a late `stop()`
  or a handshake finishing after disposal, and two simultaneous start attempts
  no longer leave a second process running.

### Data

- Engine profiles carry a stable id; profiles saved by earlier versions are
  migrated on first load. A corrupt or partially corrupt profile store no
  longer makes the Engine Manager fail to open — unreadable entries are dropped
  and the rest kept.
- A profile can no longer be edited or deleted "by position", which could
  retarget the wrong engine after a delete.

## 2.3.1

### What to test

- **Speak your moves** — tap the microphone on the game screen, say the move
  ("knight to f3", "castles", "e takes d5"; in German "Springer nach f3",
  "kurze Rochade"), and tap again. The app matches what you said against the
  legal moves and plays it; when two moves sound alike it shows the likeliest
  three to pick from. The first use downloads the speech model (142 MB) and
  asks for microphone access. Recognition runs on the device; no audio leaves
  it. English and German follow the app language.

Everything from 2.3.0 is still worth a look: Human Lens, board scanning, Your
Ghost, and the new opponents with their ratings table.

## 2.3.0

### What to test

- **Human Lens** — after a move, see how often players at your rating would
  have played it, and which moves they would have chosen instead (Maia).
- **Scan a board** — photograph a real board or a printed diagram and play or
  analyse the position. The photo models download on first use.
- **Your Ghost** — an opponent that plays your openings, learned from your
  own games, and otherwise plays like a player of your estimated rating.
- **New opponents** — ChessMamba, a zoo of chess language-model bots, and
  DeepMind's searchless transformers (9M / 136M / 270M), each with a rating
  measured against the others. Models download when first chosen.
- **Ratings table** — every bot's rating fitted from engine matches, with error
  bars.

Speaking your moves (voice input) arrived on the desktop apps first; iPhone
and iPad have it from 2.3.1.

## 2.2.0

### Engines now spend the time they are given

Four of them were not, in two different ways, and the round robin's latency
table is where it showed: every engine sat at a `late/opening` ratio of 1.00
except the ones with something wrong.

Frozenight finished searching before its clock ran out. Depth is the
difficulty setting, and at full strength the ceiling was low enough to stop
the search first — 830 of its 1554 moves ended at depth 14 with most of the
budget unspent, several of them in three milliseconds. The built-in engine did
the same in endgames, where ten plies is cheap: 149ms of a 300ms budget,
handing back half the clock in exactly the positions where another ply is
worth most. Both now stop when the time does.

Lynx did the opposite. On the web it took 408ms of a 300ms budget — time its
opponents did not get — because a move costs more than its search: setting the
position is its own trip into the .NET runtime, and that was not being counted.
It now measures the whole move and asks for correspondingly less, landing on
300ms. The desktop build had the reverse problem, reserving 50ms of every move
against losing on time in an app where every move has its own budget and there
is no clock to run out; that reserve is now 10ms.

A search that cannot be interrupted is bounded by a node count instead of a
guess about how long the next depth will take. That guess was wrong in
endgames, where iterations stay cheap for many plies and then one explodes:
two games were abandoned after an engine stopped answering. Frozenight's worst
move fell from 1111ms to 331ms of a 300ms budget as a result.

### A crashed engine no longer ends the game

Nothing watched the engine process. When one exited mid-search, nothing
completed the request: the app waited out its own timeout and reported a slow
engine, leaving the dead process in place so every later move failed the same
way until you noticed and switched engines by hand, mid-game.

A death is now noticed in milliseconds rather than seconds, reported with what
the engine printed as it went, and recovered from — the app starts a
replacement and asks it for the move. An engine that keeps dying is not
restarted forever.

Failures also say what kind they are, so a crash being recovered from reads
differently from one that needs you to pick another engine, and analysis
trouble no longer looks like trouble with the game.

### Analysis was running unbounded

The eval bar asked for a fixed depth with no clock behind it — the thing taken
out of ordinary play because a fixed depth costs whatever that depth costs in
the position in front of it. Nothing stopped it either, so a strong engine sat
at full CPU until your next move happened to interrupt it. On a phone that is
the battery. It is bounded now.

Analysis failures were also invisible on the web: two engines caught them,
wrote to a console nobody has open, and let the eval bar quietly stop updating.

### Lc0 is faster, and the web download is half the size

The engine evaluates two positions per batch rather than four and uses half the
machine's cores rather than all of them — both measured, and both the opposite
of what it was doing: four threads and a batch of four came to 1.33ms per
position against 0.74ms. That is 405 positions inside a 300ms move budget where
there were 225.

On the web it was downloading the WebGPU build of its runtime, 23MB, on a page
that cannot use WebGPU — 11MB of binary that could never be reached. It now
takes the 12MB one, served from the app rather than a public CDN, so a blocked
or unreachable CDN no longer stops the engine before it can say why.

Linux desktop builds now ship the native runtime they were missing, which they
had been silently falling back from onto a five-times slower one.

### Lc0 was not playing the game it was given

The engine scored zero out of twenty-four in the strength tournament while
making reasonable-looking moves in every position anyone spot-checked. Both
things were true, and for the same reason: the checks people run are opening
positions, and the opening position is where each of these is invisible.

Found by comparing against lc0 itself — the input planes against its encoder,
the policy against its own network output, and finally by playing it. The
harness lives in `tool/oracle/` and runs in CI.

- Two of the network's input planes were wrong. Castling rights had kingside
  and queenside swapped, for both sides; in the start position all four rights
  are set, so all four planes look identical either way. The rule-50 counter
  was divided by 100 — a scale that belongs to a different lc0 input format —
  so the network saw 0.16 where it expected 16.
- The history planes were built from every *other* ply. They were accumulated
  when the engine was asked to move, and that only happens on its own turns,
  so the network was shown a game in which the opponent never moved.
- Positions inside the search were described with the history of the position
  the search started from, so a line three moves deep was presented as a
  different game.
- One simulation used to be worse than none: the first one scored every move
  identically and picked whichever the move generator produced first, which is
  a2a3 from the start position.
- On the web, the value head had a softmax applied to numbers that were
  already probabilities, which squeezed the evaluation from ±1 into about
  ±0.36 and left the search close to value-blind.

Against lc0 on the same weights, the engine now picks the same move in 40 of
40 test positions, and its policy agrees to within 0.06%.

## 2.1.0

Engines. Most of this release is one theme: several of them were not playing
the game they claimed to, and the ones that were got slower the longer you
played.

### The engines got slower every move — they don't now

A fixed search depth costs whatever that depth costs in the position in front
of it. Measured with the built-in engine: 0.7s at the start of a game, 3-5s by
the middlegame, for the same nominal depth. Lynx, web Stockfish and Frozenight
were all driven that way and ignored the time budget the app handed them. They
now search by time, and the engines that cannot be interrupted mid-search
deepen one step at a time, checking the clock before starting a depth rather
than after.

Across a full round robin, every engine's median move time after move 20 is now
within a few percent of its median before move 10.

### The engine would stop moving a few turns in

The app thinks in the background while you do. When you moved, it asked for a
new move — and got the answer to the *previous* question, computed for a
position that no longer existed. That move was usually illegal, the board
rejected it, and the game sat on "thinking" for good. It showed up a few moves
in because that is when background thinking first outlasts a player's turn.

Searches are now serialised properly, and a move computed for an abandoned
search can never be returned for a new one. If an engine does answer with
something illegal, the app says so and hands the turn back instead of freezing.

### Frozenight could not play at all, and nobody had noticed

It applied none of the moves it was given, so it analysed the position the game
started from and answered for the wrong side. Once that was fixed it turned out
it could not castle either: it spoke castling in the internal
king-takes-rook form, which the board rejected as illegal. Both fixed. The
browser build of this engine had never been built at all — the file it loads
was missing from the app.

### Lc0 works, on every platform

It was a stub on desktop and mobile: selecting it gave you an engine that
reported an error. It now runs everywhere.

The weights it downloads were also broken — they returned nonsense for any
input, so it played nonsense. They have been re-exported from the original
Maia networks; Maia-1500 now opens 1.e4 and 1.d4 as it should. And the search
above them was not searching: it expanded the first move and then spent its
whole budget scoring every line with the *starting* position's evaluation. It
searches now, and a mate at the end of a line is scored as a mate — it used to
be scored as a loss, so the engine avoided delivering it.

### Chess960: you can castle

The chess library the app is built on assumes the king starts on e1, so in a
shuffled position it offered no castling move at all and quietly ignored the
castling rights. Added.

### Lynx on the web is 10-15x faster

Its bundle had never been compiled ahead of time. A search that took 1.6s now
takes 0.1s, and it holds a 300ms move budget where it used to overshoot into
multiple seconds. Settings offers a choice: the fast build (~6MB) or a small
one (~2MB) for slow connections.

### The app itself

Every screen redraw re-derived the move list and the game-over state by
replaying the whole game, and the clock made the screen redraw ten times a
second — so the app got heavier with every move played, and on the web that
came directly out of the engine's thinking time. Measured per redraw at move
23: 2.2ms, now 14µs.

Taking a move back used to leave the app describing a different game to the
engine than the one on the board, which is its own way of getting a nonsense
reply. Undo, PGN export and the move list now all follow the board.

### Fixed along the way

- Games that start from a position — Chess960, puzzles, a loaded FEN — were
  described to the engine as though they had started from the initial position.
- PGN export produced a file with no moves in it after a takeback.
- The move list showed PGN header tags as though they were moves after a
  takeback.
- The built-in engine could report "no legal moves" in a position that had
  plenty, when given very little time to think.
- Android release builds had been failing since before this release.
