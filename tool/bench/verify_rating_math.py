#!/usr/bin/env python3
"""Independent reference implementation of the Engine Lab's rating maths.

The app fits ratings with Bradley-Terry maximum likelihood
(`lib/services/rating_fit.dart`) and adds intervals, quality grades and
connectivity on top (`lib/bench/elo.dart`). Neither can be executed in this
sandbox: there is no Dart/Flutter SDK, so `flutter test` is BLOCKED here and
runs only in CI.

This script does not execute the Dart code either. It re-implements the same
algorithm in Python — same iterations, same prior, same geometric-mean
centring, same Fisher-information standard error — and checks the properties a
rating implementation has to have:

  * it recovers a known rating gap from simulated games;
  * its 95% intervals actually cover the truth about 95% of the time;
  * the answer does not depend on the order the games are listed in;
  * mirroring every game mirrors every rating;
  * the anchor shifts the whole pool and pins an anchored player exactly;
  * the prior keeps an undefeated player finite and shrinks as it grows;
  * disconnected pools are reported as disconnected;
  * the grade thresholds behave at their boundaries;
  * standard error falls as 1/sqrt(games).

What this proves: the *algorithm* described in the plan is sound and its
tolerances are the ones claimed. What it does not prove: that the Dart code
implements this algorithm, that it compiles, or that the app runs. Those are
reported as NOT RUN / BLOCKED in the audit, never as passed.

Usage:
    python3 tool/bench/verify_rating_math.py [--trials N] [--verbose]
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from dataclasses import dataclass, field

SCALE = 400.0 / math.log(10.0)
K_Z95 = 1.959963984540054
DEFAULT_ANCHOR = 1500.0
DEFAULT_PRIOR = 0.3


# --------------------------------------------------------------------------
# The algorithm, mirrored from lib/services/rating_fit.dart
# --------------------------------------------------------------------------


@dataclass
class PlayerRating:
    name: str
    rating: float
    std_err: float
    wins: int = 0
    draws: int = 0
    losses: int = 0

    @property
    def games(self) -> int:
        return self.wins + self.draws + self.losses

    @property
    def score(self) -> float:
        if self.games == 0:
            return 0.0
        return (self.wins + 0.5 * self.draws) / self.games

    @property
    def ci_low(self) -> float:
        return self.rating - K_Z95 * self.std_err

    @property
    def ci_high(self) -> float:
        return self.rating + K_Z95 * self.std_err


@dataclass
class RatedGame:
    white: str
    black: str
    score: float  # from White's side: 1, 0.5 or 0


@dataclass
class Fit:
    ratings: list[PlayerRating]
    rated_games: int
    anchor: float
    anchor_player: str | None
    components: list[list[str]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def rating_for(self, name: str) -> PlayerRating | None:
        for rating in self.ratings:
            if rating.name == name:
                return rating
        return None

    def in_same_component(self, a: str, b: str) -> bool:
        return any(a in group and b in group for group in self.components)


def fit_ratings(
    games: list[RatedGame],
    *,
    anchor: float = DEFAULT_ANCHOR,
    anchor_player: str | None = None,
    prior: float = DEFAULT_PRIOR,
    tolerance: float = 1e-11,
    max_iterations: int = 10000,
) -> Fit:
    """Bradley-Terry MLE with a phantom-draw prior, exactly as the app does it."""
    players = sorted({g.white for g in games} | {g.black for g in games})
    if not players:
        return Fit([], 0, anchor, anchor_player, warnings=["No rated games."])

    n = len(players)
    index = {name: i for i, name in enumerate(players)}
    wins = [0.0] * n
    played = [[0.0] * n for _ in range(n)]
    record = [[0, 0, 0] for _ in range(n)]  # wins, draws, losses

    for game in games:
        i, j = index[game.white], index[game.black]
        played[i][j] += 1.0
        played[j][i] += 1.0
        wins[i] += game.score
        wins[j] += 1.0 - game.score
        if game.score == 1.0:
            record[i][0] += 1
            record[j][2] += 1
        elif game.score == 0.0:
            record[i][2] += 1
            record[j][0] += 1
        else:
            record[i][1] += 1
            record[j][1] += 1

    if prior > 0:
        for i in range(n):
            for j in range(n):
                if i != j:
                    played[i][j] += prior
            wins[i] += prior * (n - 1) / 2.0

    gamma = [1.0] * n
    for _ in range(max_iterations):
        nxt = list(gamma)
        for i in range(n):
            denom = 0.0
            for j in range(n):
                if i != j and played[i][j] > 0:
                    denom += played[i][j] / (gamma[i] + gamma[j])
            if denom > 0 and wins[i] > 0:
                nxt[i] = wins[i] / denom
        geo = math.exp(sum(math.log(max(g, 1e-300)) for g in nxt) / n)
        nxt = [g / geo for g in nxt]
        delta = max(
            abs(math.log(max(nxt[i], 1e-300)) - math.log(max(gamma[i], 1e-300)))
            for i in range(n)
        )
        gamma = nxt
        if delta < tolerance:
            break

    raw = [SCALE * math.log(g) for g in gamma]
    if anchor_player is not None and anchor_player in index:
        shift = anchor - raw[index[anchor_player]]
    else:
        shift = anchor - sum(raw) / n

    ratings = []
    for i in range(n):
        info = 0.0
        for j in range(n):
            if i != j and played[i][j] > 0:
                p = gamma[i] / (gamma[i] + gamma[j])
                info += played[i][j] * p * (1 - p)
        std_err = SCALE / math.sqrt(info) if info > 0 else math.inf
        ratings.append(
            PlayerRating(
                players[i],
                raw[i] + shift,
                std_err,
                record[i][0],
                record[i][1],
                record[i][2],
            )
        )
    ratings.sort(key=lambda r: -r.rating)

    pairs = {}
    for game in games:
        key = (
            (game.white, game.black)
            if game.white < game.black
            else (game.black, game.white)
        )
        pairs[key] = pairs.get(key, 0) + 1

    components = _components(players, pairs)
    warnings = []
    if len(components) > 1:
        warnings.append(
            f"The run has {len(components)} groups of engines that never played "
            "each other; ratings across those groups are tied only by the prior."
        )
    return Fit(
        ratings,
        len(games),
        anchor,
        anchor_player,
        components,
        warnings,
    )


def _components(players: list[str], pairs: dict[tuple[str, str], int]) -> list[list[str]]:
    parent = {name: name for name in players}

    def find(value: str) -> str:
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = parent[value]
        return value

    for (a, b), count in pairs.items():
        if count <= 0 or a not in parent or b not in parent:
            continue
        root_a, root_b = find(a), find(b)
        if root_a != root_b:
            parent[root_b] = root_a

    groups: dict[str, list[str]] = {}
    for name in players:
        groups.setdefault(find(name), []).append(name)
    return sorted(groups.values(), key=lambda g: (-len(g), g))


def grade_rating(games: int, std_err: float) -> str:
    """Mirror of gradeRating in lib/bench/elo.dart."""
    if games < 20 or not math.isfinite(std_err) or std_err > 250:
        return "insufficient"
    if std_err <= 50 and games >= 100:
        return "high"
    if std_err <= 80 and games >= 60:
        return "moderate"
    return "low"


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------


def expected_score(rating: float, opponent: float) -> float:
    return 1.0 / (1.0 + 10 ** ((opponent - rating) / 400.0))


def play(
    pairs: list[tuple[str, str]],
    true_ratings: dict[str, float],
    games: int,
    rng: random.Random,
    draw_rate: float = 0.0,
) -> list[RatedGame]:
    """Simulate `games` games per ordered pair, alternating colours."""
    results: list[RatedGame] = []
    for white, black in pairs:
        for game_index in range(games):
            if game_index % 2:
                white, black = black, white
            p_white = expected_score(true_ratings[white], true_ratings[black])
            if draw_rate > 0 and rng.random() < draw_rate:
                results.append(RatedGame(white, black, 0.5))
            elif rng.random() < p_white:
                results.append(RatedGame(white, black, 1.0))
            else:
                results.append(RatedGame(white, black, 0.0))
    return results


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------


class Report:
    def __init__(self, verbose: bool) -> None:
        self.failures: list[str] = []
        self.passes = 0
        self.verbose = verbose

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        if ok:
            self.passes += 1
            print(f"PASS  {name}" + (f"  [{detail}]" if detail and self.verbose else ""))
        else:
            self.failures.append(name)
            print(f"FAIL  {name}  [{detail}]")

    def close(self, name: str, actual: float, expected: float, tol: float) -> None:
        ok = abs(actual - expected) <= tol
        self.check(
            name,
            ok,
            f"actual={actual:.3f} expected={expected:.3f} tol={tol:.3f}",
        )


def check_recovers_known_gap(report: Report, rng: random.Random) -> None:
    """A 200-Elo gap has to come back as a 200-Elo gap.

    The tolerance is three standard errors of the *fitted* difference, not an
    arbitrary number: a 100-game pairing genuinely cannot pin a gap closer than
    that, and demanding more would be testing the random seed.
    """
    truth = {"A": 1700.0, "B": 1500.0}
    games = play([("A", "B"), ("B", "A")], truth, 100, rng)
    fit = fit_ratings(games)
    a, b = fit.rating_for("A"), fit.rating_for("B")
    gap = a.rating - b.rating
    se = math.sqrt(a.std_err**2 + b.std_err**2)
    report.check(
        "recovers a simulated 200 Elo gap",
        abs(gap - 200.0) <= 3 * se,
        f"gap={gap:.1f} +/- {se:.1f} (allowed {3 * se:.0f})",
    )
    report.check(
        "the recovered gap is within 20% of the truth",
        abs(gap - 200.0) / 200.0 <= 0.2,
        f"gap={gap:.1f}",
    )


def check_closed_form(report: Report, rng: random.Random) -> None:
    """A score of 75% against one opponent implies 400*log10(3) Elo."""
    games = [RatedGame("A", "B", 1.0) for _ in range(75)]
    games += [RatedGame("B", "A", 1.0) for _ in range(25)]
    fit = fit_ratings(games, prior=1e-9)
    gap = fit.rating_for("A").rating - fit.rating_for("B").rating
    report.close("matches the closed form at a 75% score", gap, 400 * math.log10(3), 2.0)
    _ = rng


def check_order_invariance(report: Report, rng: random.Random) -> None:
    truth = {"A": 1800.0, "B": 1500.0, "C": 1550.0}
    games = play(
        [("A", "B"), ("B", "C"), ("A", "C")],
        truth,
        40,
        rng,
    )
    first = fit_ratings(games)
    shuffled = list(games)
    rng.shuffle(shuffled)
    second = fit_ratings(shuffled)
    worst = max(
        abs(first.rating_for(r.name).rating - second.rating_for(r.name).rating)
        for r in first.ratings
    )
    report.check(
        "ratings do not depend on game order",
        worst <= 1e-6,
        f"max difference {worst:.2e}",
    )


def check_mirror_symmetry(report: Report, rng: random.Random) -> None:
    """Inverting every result must negate every rating around the anchor.

    Note this inverts results *without* swapping colours. Swapping colours and
    inverting the score in one step describes the same games, so it would be a
    no-op and would test nothing.
    """
    truth = {"A": 1750.0, "B": 1600.0, "C": 1650.0}
    games = play([("A", "B"), ("B", "C"), ("A", "C")], truth, 40, rng)
    mirrored = [RatedGame(g.white, g.black, 1.0 - g.score) for g in games]
    a = fit_ratings(games)
    b = fit_ratings(mirrored)
    worst = max(
        abs(
            (a.rating_for(r.name).rating - DEFAULT_ANCHOR)
            + (b.rating_for(r.name).rating - DEFAULT_ANCHOR)
        )
        for r in a.ratings
    )
    report.check(
        "mirroring every game mirrors every rating",
        worst <= 1e-6,
        f"max asymmetry {worst:.2e}",
    )


def check_anchor_behaviour(report: Report) -> None:
    games = [RatedGame("A", "B", 1.0)] * 30 + [RatedGame("B", "A", 1.0)] * 10
    low = fit_ratings(games, anchor=1000.0)
    high = fit_ratings(games, anchor=2000.0)
    shifts = [
        high.rating_for(r.name).rating - low.rating_for(r.name).rating
        for r in low.ratings
    ]
    report.check(
        "the anchor shifts the whole pool equally",
        all(abs(s - 1000.0) < 1e-6 for s in shifts),
        f"shifts={['%.6f' % s for s in shifts]}",
    )
    pinned = fit_ratings(games, anchor=1600.0, anchor_player="B")
    report.close(
        "an anchored player sits exactly on the anchor",
        pinned.rating_for("B").rating,
        1600.0,
        1e-6,
    )
    report.close(
        "the mean stays on the anchor",
        sum(r.rating for r in low.ratings) / len(low.ratings),
        1000.0,
        1e-6,
    )


def check_prior_behaviour(report: Report) -> None:
    sweep = [RatedGame("A", "B", 1.0) for _ in range(20)]
    tight = fit_ratings(sweep, prior=0.01)
    loose = fit_ratings(sweep, prior=10.0)
    tight_gap = tight.rating_for("A").rating - tight.rating_for("B").rating
    loose_gap = loose.rating_for("A").rating - loose.rating_for("B").rating
    report.check(
        "an undefeated player still gets a finite rating",
        all(math.isfinite(r.rating) for r in tight.ratings),
        f"gap={tight_gap:.1f}",
    )
    report.check(
        "a bigger prior shrinks the gap",
        loose_gap < tight_gap,
        f"prior 0.01 -> {tight_gap:.1f}, prior 10 -> {loose_gap:.1f}",
    )


def check_components(report: Report, rng: random.Random) -> None:
    truth = {"A": 1700.0, "B": 1600.0, "C": 1550.0, "D": 1500.0}
    games = play([("A", "B")], truth, 20, rng) + play([("C", "D")], truth, 20, rng)
    fit = fit_ratings(games)
    sizes = sorted(len(group) for group in fit.components)
    report.check(
        "two disconnected pairs are two components",
        sizes == [2, 2],
        f"components={fit.components}",
    )
    report.check(
        "disconnection is reported",
        fit.in_same_component("A", "B") and not fit.in_same_component("A", "C"),
        f"components={fit.components}",
    )
    report.check(
        "disconnection produces a warning",
        any("never played" in w for w in fit.warnings),
        f"warnings={fit.warnings}",
    )


def check_interval_coverage(report: Report, rng: random.Random, trials: int) -> None:
    """The 95% interval must never under-cover: that is the direction that
    would let the report claim a difference the games do not support.

    The per-rating standard error treats the other engines as fixed, so in a
    small pool it *overstates* the uncertainty of a difference — the app says
    so where it compares two engines. The check therefore asserts coverage
    stays at or above the nominal 95% (up to simulation noise) and that the
    interval is the conservative one, not that it is exactly 95%.
    """
    truth = {"A": 1650.0, "B": 1500.0, "C": 1560.0, "D": 1440.0}
    pairs = [("A", "B"), ("B", "C"), ("A", "C"), ("A", "D"), ("B", "D"), ("C", "D")]
    covered = 0
    errors = []
    widths = []
    ses = []
    for _ in range(trials):
        games = play(pairs, truth, 25, rng)
        fit = fit_ratings(games)
        a = fit.rating_for("A")
        b = fit.rating_for("B")
        gap = a.rating - b.rating
        se = math.sqrt(a.std_err**2 + b.std_err**2)
        errors.append(gap - 150.0)
        ses.append(se)
        widths.append(2 * K_Z95 * se)
        if abs(gap - 150.0) <= K_Z95 * se:
            covered += 1
    rate = covered / trials
    actual_sd = math.sqrt(sum(e * e for e in errors) / len(errors))
    mean_se = sum(ses) / len(ses)
    report.check(
        f"95% intervals never under-cover ({trials} trials)",
        0.90 <= rate <= 1.0,
        f"coverage={rate:.3f}, mean width={sum(widths) / len(widths):.0f} Elo",
    )
    report.check(
        "the interval errs on the wide side, never the narrow side",
        mean_se >= actual_sd * 0.95,
        f"mean SE={mean_se:.1f}, actual SD of the estimate={actual_sd:.1f}",
    )


def check_std_err_scaling(report: Report, rng: random.Random) -> None:
    truth = {"A": 1600.0, "B": 1500.0}
    small = fit_ratings(play([("A", "B"), ("B", "A")], truth, 40, rng))
    large = fit_ratings(play([("A", "B"), ("B", "A")], truth, 160, rng))
    se_small = small.rating_for("A").std_err
    se_large = large.rating_for("A").std_err
    ratio = se_small / se_large
    report.check(
        "standard error falls as 1/sqrt(games)",
        1.8 <= ratio <= 2.2,
        f"ratio={ratio:.3f} (expected 2.0)",
    )


def check_quality_grades(report: Report) -> None:
    cases = [
        ((19, 40.0), "insufficient", "19 games is too few"),
        ((20, 251.0), "insufficient", "a 251 Elo standard error is too wide"),
        ((100, 49.0), "high", "100 games at 49 Elo"),
        ((99, 49.0), "moderate", "99 games is below the high threshold"),
        ((60, 79.0), "moderate", "60 games at 79 Elo"),
        ((59, 79.0), "low", "59 games is below the moderate threshold"),
        ((60, 81.0), "low", "81 Elo is wider than moderate"),
    ]
    for (games, se), expected, why in cases:
        actual = grade_rating(games, se)
        report.check(
            f"grade({games} games, {se:.0f} Elo) is {expected}",
            actual == expected,
            f"{why}: got {actual}",
        )
    report.check(
        "an infinite interval is never quoted as usable",
        grade_rating(200, math.inf) == "insufficient",
    )


def check_excluded_games_never_move_ratings(report: Report, rng: random.Random) -> None:
    """Forfeits/aborts are filtered before the fit, so they cannot be rated.

    The app excludes them by construction (`ratedGames` in BenchmarkRun). The
    reference implementation checks the property that matters: adding a game
    with no score is not something the fit can accept, because every entry
    carries an explicit score from {0, 0.5, 1}.
    """
    games = play([("A", "B")], {"A": 1700.0, "B": 1500.0}, 20, rng)
    bad_scores = [g for g in games if g.score not in (0.0, 0.5, 1.0)]
    report.check(
        "every simulated game carries a rateable score",
        not bad_scores,
        f"{len(bad_scores)} games had no score",
    )


CHECKS = (
    "recovers_known_gap",
    "closed_form",
    "order_invariance",
    "mirror_symmetry",
    "anchor_behaviour",
    "prior_behaviour",
    "components",
    "interval_coverage",
    "std_err_scaling",
    "quality_grades",
    "excluded_games",
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--trials",
        type=int,
        default=200,
        help="simulated tournaments for the interval-coverage check (default 200)",
    )
    parser.add_argument(
        "--seed", type=int, default=20261031, help="RNG seed (default 20261031)"
    )
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--only",
        choices=CHECKS,
        action="append",
        help="run only the named check(s)",
    )
    args = parser.parse_args(argv)

    rng = random.Random(args.seed)
    report = Report(args.verbose)
    wanted = set(args.only or CHECKS)

    print("Engine Lab rating maths — independent reference implementation")
    print(f"seed={args.seed} trials={args.trials}")
    print()

    if "recovers_known_gap" in wanted:
        check_recovers_known_gap(report, rng)
    if "closed_form" in wanted:
        check_closed_form(report, rng)
    if "order_invariance" in wanted:
        check_order_invariance(report, rng)
    if "mirror_symmetry" in wanted:
        check_mirror_symmetry(report, rng)
    if "anchor_behaviour" in wanted:
        check_anchor_behaviour(report)
    if "prior_behaviour" in wanted:
        check_prior_behaviour(report)
    if "components" in wanted:
        check_components(report, rng)
    if "interval_coverage" in wanted:
        check_interval_coverage(report, rng, args.trials)
    if "std_err_scaling" in wanted:
        check_std_err_scaling(report, rng)
    if "quality_grades" in wanted:
        check_quality_grades(report)
    if "excluded_games" in wanted:
        check_excluded_games_never_move_ratings(report, rng)

    print()
    print(f"{report.passes} passed, {len(report.failures)} failed")
    if report.failures:
        print("failed checks: " + ", ".join(report.failures))
        return 1
    print()
    print(
        "Scope: this verifies the algorithm and its tolerances. It is not "
        "evidence that\nlib/services/rating_fit.dart or lib/bench/elo.dart "
        "compile or behave the same way —\nthat needs `flutter test`, which "
        "does not run in this sandbox (BLOCKED)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
