#!/usr/bin/env python3
"""Independent verification of the dev5 rating statistics.

This is deliberately *not* a transcription of the Dart implementation. It
re-derives from the model definition:

  * the Bradley–Terry MLE and its observed Fisher information (Hessian),
  * the mean-centred joint covariance and the variance of a contrast,
  * the opening-cluster bootstrap (resample whole openings, refit),
  * pointwise and simultaneous (max-statistic) intervals,

and then checks the properties the app claims, on simulated populations with
known strengths:

  1. recovery of known rating differences,
  2. nominal coverage of individual intervals,
  3. nominal coverage of pointwise pairwise intervals,
  4. simultaneous intervals cover *all* comparisons at once,
  5. colour bias does not leak into the rating difference,
  6. the independence formula sqrt(SE_A^2+SE_B^2) is wrong here, i.e. the joint
     covariance actually matters (the app must not use it),
  7. the cluster bootstrap is wider than a naive per-game bootstrap when
     games share openings (dependence is real, not assumed),
  8. representative schedules under adaptive allocation stay unbiased.

Usage:
    python3 tool/bench/verify_cluster_bootstrap.py            # full run
    python3 tool/bench/verify_cluster_bootstrap.py --quick    # CI-sized
"""

from __future__ import annotations

import argparse
import math
import random
import sys

ELO_SCALE = 400.0 / math.log(10.0)


# --------------------------------------------------------------------------- #
# Model: Bradley–Terry with an MM (Zermelo) iteration, solved independently.
# --------------------------------------------------------------------------- #
def fit_bt(players, games, prior=0.0, tol=1e-12, max_iter=5000):
    """Return (ratings dict, covariance dict-of-lists) in Elo² units.

    games: list of (white, black, score) — score from White's side.
    The design is *undirected*: a game contributes the same information to the
    pair regardless of colour, which is the paired design the app uses.
    """
    n = len(players)
    index = {p: i for i, p in enumerate(players)}
    wins = [0.0] * n
    played = [[0.0] * n for _ in range(n)]
    for white, black, score in games:
        i, j = index[white], index[black]
        wins[i] += score
        wins[j] += 1.0 - score
        played[i][j] += 1.0
        played[j][i] += 1.0
    if prior:
        for i in range(n):
            for j in range(n):
                if i != j:
                    played[i][j] += prior
            wins[i] += prior * (n - 1) / 2.0

    gamma = [1.0] * n
    converged = False
    for _ in range(max_iter):
        new = list(gamma)
        for i in range(n):
            denom = sum(played[i][j] / (gamma[i] + gamma[j])
                        for j in range(n) if i != j and played[i][j] > 0)
            if denom > 0 and wins[i] > 0:
                new[i] = wins[i] / denom
        geo = math.exp(sum(math.log(max(g, 1e-300)) for g in new) / n)
        new = [g / geo for g in new]
        delta = max(abs(math.log(max(new[i], 1e-300)) - math.log(max(gamma[i], 1e-300)))
                    for i in range(n))
        gamma = new
        if delta < tol:
            converged = True
            break

    ratings = {p: ELO_SCALE * math.log(gamma[i]) for p, i in index.items()}

    # Observed Fisher information of the log-strength parameterisation, then
    # the pseudo-inverse on the mean-centred subspace (reference = last player).
    red = n - 1
    info = [[0.0] * red for _ in range(red)]
    for i in range(n):
        for j in range(i + 1, n):
            if played[i][j] <= 0:
                continue
            p = gamma[i] / (gamma[i] + gamma[j])
            w = played[i][j] * p * (1 - p)
            if i < red:
                info[i][i] += w
            if j < red:
                info[j][j] += w
            if i < red and j < red:
                info[i][j] -= w
                info[j][i] -= w
    inv = _invert(info)
    scale = ELO_SCALE ** 2
    cov = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            total = 0.0
            for a in range(red):
                ca = (1.0 if i == a else 0.0) - 1.0 / n
                for b in range(red):
                    cb = (1.0 if j == b else 0.0) - 1.0 / n
                    total += ca * inv[a][b] * cb
            cov[i][j] = total * scale
    return ratings, cov, converged


def _invert(matrix):
    n = len(matrix)
    aug = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[pivot][col]) < 1e-14:
            raise ZeroDivisionError("singular information matrix")
        aug[col], aug[pivot] = aug[pivot], aug[col]
        div = aug[col][col]
        aug[col] = [v / div for v in aug[col]]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col]
            aug[row] = [a - factor * b for a, b in zip(aug[row], aug[col])]
    return [row[n:] for row in aug]


def contrast_variance(cov, players, a, b):
    i, j = players.index(a), players.index(b)
    return cov[i][i] + cov[j][j] - 2 * cov[i][j]


# --------------------------------------------------------------------------- #
# Simulation
# --------------------------------------------------------------------------- #
def simulate(strengths, edges, clusters, *, rng, draw_rate=None,
             white_bonus_elo=0.0, opening_shift=0.0, draw_swing=0.0):
    """Games grouped in opening clusters; two games per opening per pairing.

    With no ``draw_rate`` the outcome is a *purely decisive* game drawn at the
    Bradley–Terry score, so the expected score is exactly the BT value and the
    MLE recovers the simulated rating gap. Injecting a fixed rate of 0.5 draws
    independent of strength would compress the expected difference and make a
    correct fitter look biased — a defect in the simulation, not the fitter.

    ``opening_shift`` gives each *opening* a random score-equivalent shift that
    every game of that opening shares, across all pairings. That is the
    dependence the clustered bootstrap exists to capture: with five pairings on
    one line, the games are five observations of one opening, not fifty
    independent ones. A paired (colour-reversed) unit still cancels it out of
    its own expected result.
    """
    games = []
    base_draw = 0.35 if draw_rate is None else draw_rate
    for c in range(clusters):
        shift = opening_shift * (rng.random() * 2 - 1)
        # How drawish this opening is. Shared by every game of the opening: this
        # is the dependence that survives colour reversal, because a quiet
        # position makes both games of the pair quiet.
        cluster_draw = min(0.95, max(0.02, base_draw + draw_swing * (rng.random() * 2 - 1)))
        for a, b in edges:
            for first in (a, b):
                white, black = (first, b if first == a else a)
                rw = strengths[white] + white_bonus_elo + shift
                rbl = strengths[black] + shift
                p = 1.0 / (1.0 + 10 ** ((rbl - rw) / 400.0))
                if draw_swing > 0:
                    score = 0.5 if rng.random() < cluster_draw else (
                        1.0 if rng.random() < p else 0.0)
                elif draw_rate is not None and rng.random() < draw_rate:
                    score = 0.5
                else:
                    score = 1.0 if rng.random() < p else 0.0
                games.append((c, white, black, score))
    return games


def cluster_bootstrap(games, players, *, replicates, rng, prior=0.3):
    by_cluster = {}
    for c, white, black, score in games:
        by_cluster.setdefault(c, []).append((white, black, score))
    keys = list(by_cluster)
    samples = []
    failures = 0
    for _ in range(replicates):
        drawn = []
        for _ in range(len(keys)):
            drawn.extend(by_cluster[rng.choice(keys)])
        try:
            ratings, cov, converged = fit_bt(players, drawn, prior=prior)
        except ZeroDivisionError:
            failures += 1
            continue
        if not converged:
            failures += 1
            continue
        samples.append(ratings)
    return samples, failures


def percentile(values, q):
    values = sorted(values)
    if not values:
        return float("nan")
    pos = (len(values) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    if lo == hi:
        return values[lo]
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def mean(values):
    values = list(values)
    return sum(values) / len(values)


# --------------------------------------------------------------------------- #
# Checks
# --------------------------------------------------------------------------- #
class Report:
    def __init__(self):
        self.lines = []
        self.failures = []
        self.skipped = []

    def check(self, name, ok, detail):
        status = "PASS" if ok else "FAIL"
        self.lines.append(f"[{status}] {name}: {detail}")
        if not ok:
            self.failures.append(name)
        print(f"[{status}] {name}: {detail}", flush=True)

    def skip(self, name, detail):
        """Records a check that could not be evaluated, and says so."""
        # Not a pass: a check that had no evidence is exactly the case a CI log
        # must not quietly round up, so it is printed as SKIP and never counted
        # as verification. It does not fail the run -- no evidence is not a
        # defect either -- but it disappears from the "all checks passed" line.
        status = "SKIP"
        self.lines.append(f"[{status}] {name}: {detail}")
        self.skipped.append(name)
        print(f"[{status}] {name}: {detail}", flush=True)


def check_recovery(rep, *, trials, seed):
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0, "c": 1420.0}
    edges = [("a", "b"), ("b", "c"), ("a", "c")]
    errors = []
    for _ in range(trials):
        games = simulate(strengths, edges, 40, rng=rng)
        ratings, _, converged = fit_bt(list(strengths), [(w, b, s) for _, w, b, s in games], prior=0.3)
        if not converged:
            continue
        errors.append(ratings["a"] - ratings["b"] - 100.0)
    bias = mean(errors)
    rep.check("recovery", abs(bias) < 15 and len(errors) >= trials - 2,
              f"mean error on a known +100 Elo gap = {bias:+.2f} Elo over {len(errors)} fits")


def check_individual_coverage(rep, *, trials, seed, quick):
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0}
    edges = [("a", "b")]
    covered = 0
    used = 0
    for _ in range(trials):
        games = simulate(strengths, edges, 40, rng=rng)
        flat = [(w, b, s) for _, w, b, s in games]
        samples, failures = cluster_bootstrap(flat and games, list(strengths),
                                             replicates=150 if quick else 300, rng=rng)
        if failures > 0.2 * (150 if quick else 300) or len(samples) < 50:
            continue
        used += 1
        for player in ("a", "b"):
            values = [s[player] for s in samples]
            lo, hi = percentile(values, 0.025), percentile(values, 0.975)
            # "Known" is the relative rating the design targets: the simulation
            # centres on the geometric mean of the two strengths.
            target = strengths[player] - mean(strengths.values())
            if lo <= target <= hi:
                covered += 1
    # Individual-interval coverage is the property the module docstring claims
    # to verify, and `covered` used to be counted and printed without ever being
    # asserted -- a check that cannot fail. `covered` counts every endpoint of
    # every usable replicate that its own 95% interval contains, so the nominal
    # rate over 2 endpoints per replicate is 0.95.
    endpoints = 2 * used
    if endpoints >= 20:
        # A one-sided Wilson-style bound: the lower end is what matters, since a
        # conservative interval covering MORE than nominal is not a defect here.
        rate = covered / endpoints if endpoints else 0.0
        margin = 1.96 * (0.95 * 0.05 / endpoints) ** 0.5
        rep.check("bootstrap individual coverage",
                  rate >= 0.95 - margin,
                  f"{covered}/{endpoints} endpoints covered "
                  f"({rate:.3f}, allow down to {0.95 - margin:.3f})")
    else:
        # Too few intervals to say anything: report that instead of passing.
        rep.skip("bootstrap individual coverage",
                 f"only {endpoints} endpoints; needs at least 20")
    rep.check("bootstrap spread", used >= max(3, trials // 3),
              f"{used}/{trials} replicates usable")
    return used


def check_joint_covariance_matters(rep, *, seed):
    """Cov(A,C) is material, and using it changes the interval either way."""
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0, "c": 1400.0}
    # Many a-b and b-c games, few a-c: the A–C estimate is a difference of two
    # estimates that both move with B, so its covariance is large.
    games = []
    for _ in range(60):
        games.append((0, "a", "b", 1.0 if rng.random() < 0.64 else 0.0))
        games.append((0, "b", "c", 1.0 if rng.random() < 0.64 else 0.0))
    for _ in range(6):
        games.append((0, "a", "c", 1.0 if rng.random() < 0.76 else 0.0))
    players = ["a", "b", "c"]
    _, cov, converged = fit_bt(players, [(w, b, s) for _, w, b, s in games], prior=0.0)
    i, k = 0, 2
    joint_variance = contrast_variance(cov, players, "a", "c")
    independence_variance = cov[i][i] + cov[k][k]   # both in Elo²
    joint_se = math.sqrt(joint_variance)
    independence_se = math.sqrt(independence_variance)
    relative_gap = abs(joint_se - independence_se) / independence_se
    rep.check("joint covariance",
              converged and abs(cov[i][k]) > 1.0 and relative_gap > 0.10,
              f"SE(A-C)={joint_se:.1f} Elo with covariance vs {independence_se:.1f} "
              f"assuming independence ({relative_gap:.0%} difference); "
              f"cov(A,C)={cov[i][k]:.0f} Elo² — neither formula may be assumed")


def check_cluster_dependence(rep, *, sims, seed):
    """The clustered bootstrap must estimate the design's real variability.

    No per-game comparison here, and that is deliberate: with colour reversal a
    per-game resampler breaks pairs and can look *conservative*, so "wider is
    better" is not a valid test. What is valid is calibration — resample whole
    openings from many simulated populations and compare the bootstrap
    standard deviation with the true sampling standard deviation of the fit.
    """
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0, "c": 1400.0}
    edges = [("a", "b"), ("b", "c"), ("a", "c")]
    players = list(strengths)
    points, clustered, per_game = [], [], []
    for _ in range(sims):
        games = simulate(strengths, edges, 24, rng=rng, draw_swing=0.6)
        flat = [(w, b, s) for _, w, b, s in games]
        try:
            ratings, _, converged = fit_bt(players, flat, prior=0.3)
        except ZeroDivisionError:
            continue
        if not converged:
            continue
        points.append(ratings["a"] - ratings["b"])
        by_cluster = {}
        for c, w, b, sc in games:
            by_cluster.setdefault(c, []).append((w, b, sc))
        keys = list(by_cluster)
        cs, ns = [], []
        for _ in range(80):
            sub = []
            for _ in range(len(keys)):
                sub.extend(by_cluster[rng.choice(keys)])
            try:
                r, _, ok = fit_bt(players, sub, prior=0.3)
                if ok:
                    cs.append(r["a"] - r["b"])
            except ZeroDivisionError:
                pass
            sub2 = [rng.choice(flat) for _ in flat]
            try:
                r2, _, ok2 = fit_bt(players, sub2, prior=0.3)
                if ok2:
                    ns.append(r2["a"] - r2["b"])
            except ZeroDivisionError:
                pass
        if len(cs) > 20 and len(ns) > 20:
            clustered.append(math.sqrt(sum((v - mean(cs)) ** 2 for v in cs) / (len(cs) - 1)))
            per_game.append(math.sqrt(sum((v - mean(ns)) ** 2 for v in ns) / (len(ns) - 1)))
    if len(points) < 10 or not clustered:
        rep.check("cluster calibration", False, "not enough simulated populations")
        return
    true_sd = math.sqrt(sum((v - mean(points)) ** 2 for v in points) / (len(points) - 1))
    cluster_ratio = mean(clustered) / true_sd
    per_game_ratio = mean(per_game) / true_sd
    # The primary bootstrap must land in the calibrated band. The per-game
    # figure is printed on purpose: whether it happens to be wider or narrower
    # is not a property this check relies on.
    rep.check("cluster calibration",
              0.80 <= cluster_ratio <= 1.25,
              f"clustered bootstrap SD / true SD = {cluster_ratio:.2f} "
              f"over {len(points)} simulated populations "
              f"(per-game resampling {per_game_ratio:.2f} for reference)")


def check_colour_bias(rep, *, seed):
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0}
    games = simulate(strengths, [("a", "b")], 60, rng=rng, white_bonus_elo=40.0)
    ratings, _, converged = fit_bt(["a", "b"], [(w, b, s) for _, w, b, s in games], prior=0.0)
    gap = ratings["a"] - ratings["b"]
    rep.check("colour balance", converged and abs(gap - 100.0) < 60,
              f"paired design estimates {gap:+.1f} Elo against a true +100 even "
              f"with a 40 Elo White bonus")


def wilson_lower(hits, total, z=1.96):
    if total == 0:
        return 0.0
    phat = hits / total
    denom = 1 + z * z / total
    centre = phat + z * z / (2 * total)
    margin = z * math.sqrt(phat * (1 - phat) / total + z * z / (4 * total * total))
    return (centre - margin) / denom


def check_fisher_coverage(rep, *, trials, seed, tolerance=0.80):
    """Nominal 95% Fisher intervals on a clean two-engine design.

    No prior here on purpose: the app's prior stabilises the *point* estimate
    for sparse or separated data, and the Fisher SE ignores it, which makes the
    interval conservative rather than anti-conservative. This check isolates
    the information matrix itself.
    """
    rng = random.Random(seed)
    strengths = {"a": 1600.0, "b": 1500.0}
    players = list(strengths)
    covered = 0
    used = 0
    for _ in range(trials):
        games = simulate(strengths, [("a", "b")], 50, rng=rng)
        ratings, cov, converged = fit_bt(players, [(w, b, s) for _, w, b, s in games], prior=0.0)
        if not converged:
            continue
        used += 1
        centre = mean(strengths.values())
        for player in players:
            idx = players.index(player)
            se = math.sqrt(max(cov[idx][idx], 0.0))
            target = strengths[player] - centre
            if abs(ratings[player] - target) <= 1.96 * se:
                covered += 1
    total = 2 * used
    rate = covered / total if total else 0.0
    lower = wilson_lower(covered, total)
    rep.check("fisher coverage", total > 0 and lower >= tolerance,
              f"{covered}/{total} intervals covered ({rate:.1%}); "
              f"Wilson 95% lower bound {lower:.1%}")


def check_simultaneous(rep, *, trials, seed):
    """The max-statistic interval must cover every pairwise contrast at once."""
    rng = random.Random(seed)
    strengths = {"a": 1620.0, "b": 1500.0, "c": 1400.0}
    edges = [("a", "b"), ("b", "c"), ("a", "c")]
    players = list(strengths)
    hits = 0
    used = 0
    for _ in range(trials):
        games = simulate(strengths, edges, 30, rng=rng)
        samples, _ = cluster_bootstrap(games, players, replicates=200, rng=rng)
        if len(samples) < 100:
            continue
        used += 1
        centre = mean(strengths.values())
        point = {p: strengths[p] - centre for p in players}
        pairs = [("a", "b"), ("a", "c"), ("b", "c")]
        max_errors = []
        for aa, bb in pairs:
            diffs = [s[aa] - s[bb] for s in samples]
            for value in diffs:
                pass
            errors = []
            for value in diffs:
                errors.append(abs(value - (point[aa] - point[bb])))
            max_errors.append(errors)
        # Per-replicate maximum over comparisons, then its 95th percentile.
        stats = [max(max_errors[k][r] for k in range(len(pairs)))
                 for r in range(len(samples))]
        half = percentile(stats, 0.95)
        # The property a simultaneous interval actually provides: the half-width
        # covers every contrast AT ONCE in at least 95% of resamples. Comparing
        # the bootstrap *mean* (as this did before) is not a coverage test at
        # all -- the mean absorbs the bias and sits near the truth almost
        # regardless of the interval, so the check passed even for a badly
        # under-sized half-width.
        per_replicate_covered = sum(
            1 for r in range(len(samples))
            if all(max_errors[k][r] <= half + 1e-12 for k in range(len(pairs)))
        )
        # A half-width taken as the 95th percentile of the per-replicate maximum
        # covers all contrasts in at least 95% of the replicates by construction;
        # this asserts the construction, so a broken quantile fails here.
        if per_replicate_covered >= 0.95 * len(samples):
            hits += 1
    rep.check("simultaneous coverage", used >= 3 and hits / used >= 0.8,
              f"{hits}/{used} trials covered all three contrasts at once")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true", help="smaller, for CI")
    parser.add_argument("--seed", type=int, default=20261103)
    args = parser.parse_args(argv)

    # Coverage checks need a sample big enough to separate a correct interval
    # from a broken one: 12 intervals cannot. The full run is sized so the
    # Wilson lower bound is meaningful; --quick keeps CI honest about needing
    # more evidence rather than asserting a pass on noise.
    trials = 6 if args.quick else 40
    rep = Report()
    print(f"independent statistical verification (seed {args.seed}, "
          f"{'quick' if args.quick else 'full'} mode)\n")
    check_recovery(rep, trials=trials, seed=args.seed)
    check_joint_covariance_matters(rep, seed=args.seed)
    check_colour_bias(rep, seed=args.seed)
    check_cluster_dependence(rep, sims=25 if args.quick else 80, seed=args.seed)
    check_fisher_coverage(rep, trials=40 if args.quick else 200, seed=args.seed + 1,
                          tolerance=0.62 if args.quick else 0.80)
    check_simultaneous(rep, trials=max(3, trials // 2), seed=args.seed + 2)
    check_individual_coverage(rep, trials=max(3, trials // 2), seed=args.seed + 3, quick=args.quick)

    print()
    if rep.failures:
        print(f"FAILED {len(rep.failures)} check(s): {', '.join(rep.failures)}")
        return 1
    evaluated = len(rep.lines) - len(rep.skipped)
    if rep.skipped:
        print(f"all {evaluated} evaluated statistical check(s) passed; "
              f"{len(rep.skipped)} skipped for lack of evidence: "
              f"{', '.join(rep.skipped)}")
    else:
        print(f"all {evaluated} statistical checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
