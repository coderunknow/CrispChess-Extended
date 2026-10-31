import importlib.util
from pathlib import Path
import sys
import unittest
import math

PATH = Path(__file__).resolve().parents[2] / 'tool/bench/verify_rating_math.py'
spec = importlib.util.spec_from_file_location('lab_rating_reference', PATH)
reference = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = reference
spec.loader.exec_module(reference)


class ReferenceTests(unittest.TestCase):
    def test_observed_centered_two_player_error(self):
        games = [reference.RatedGame('a', 'b', 0.5) for _ in range(100)]
        fit = reference.fit_ratings(games)
        expected = reference.SCALE / (2 * math.sqrt(100 * 0.25))
        self.assertAlmostEqual(fit.rating_for('a').std_err, expected)
        # Phantom prior must not manufacture statistical information.
        large_prior = reference.fit_ratings(games, prior=100)
        self.assertAlmostEqual(large_prior.rating_for('a').std_err, expected)

    def test_other_disconnected_pool_cannot_change_a_fit(self):
        games = [reference.RatedGame('a', 'b', 1.0)] * 20
        separate = reference.fit_ratings(games)
        joint = reference.fit_ratings(games + [reference.RatedGame('c', 'd', 0.0)] * 40)
        self.assertAlmostEqual(separate.rating_for('a').rating, joint.rating_for('a').rating)
        self.assertAlmostEqual(separate.rating_for('a').std_err, joint.rating_for('a').std_err)
        self.assertFalse(joint.in_same_component('a', 'c'))
