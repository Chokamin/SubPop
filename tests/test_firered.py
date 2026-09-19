import itertools
import unittest
import numpy as np
from probes.firered_alignment import forced_align


def collapse(path):
    return [v for i,v in enumerate(path) if v and (not i or v != path[i-1])]


class FireRedAlignmentTests(unittest.TestCase):
    def test_matches_exhaustive_ctc_paths_including_repeated_tokens(self):
        rng = np.random.default_rng(70)
        for tokens in ([1], [1,2], [1,1], [2,1,2]):
            for _ in range(5):
                scores = rng.normal(size=(6,3))
                result = forced_align(scores, tokens)
                candidates = [p for p in itertools.product(range(3), repeat=6) if collapse(p) == list(tokens)]
                best = max(sum(scores[t,v] for t,v in enumerate(p)) for p in candidates)
                self.assertEqual(collapse(result), list(tokens))
                self.assertAlmostEqual(sum(scores[t,v] for t,v in enumerate(result)), best)

    def test_impossible_alignment_does_not_fabricate_timestamps(self):
        for scores,tokens in [(np.zeros((2,3)),[1,1]),(np.zeros((0,3)),[1]),
                              (np.zeros((3,3)),[0]),(np.full((3,3),np.nan),[1])]:
            with self.assertRaises(ValueError):forced_align(scores,tokens)
