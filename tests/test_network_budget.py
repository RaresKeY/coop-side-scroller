import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('budget', Path(__file__).resolve().parents[1] / 'tools/network_budget.py')
budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(budget)


class NetworkBudgetTests(unittest.TestCase):
    def test_shared_allowance_reserve_and_both_players(self):
        result = budget.estimate(12, 1000, 1000, 100, 200)
        self.assertEqual(result['gameplay_egress_gb'], 43.2)
        self.assertEqual(result['match_hours_within_planning_budget'], 16203.7)
        self.assertFalse(result['enforces_spending_cap'])

    def test_no_budget_and_invalid_values(self):
        self.assertFalse(budget.estimate(12, 1, 1000, 900, 200)['fits_planning_budget'])
        for value in (0, -1, float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                budget.estimate(value, 1)

    def test_extreme_values_never_emit_nonfinite_json_or_divide_by_zero(self):
        # Scale before multiplying to keep this representable estimate valid.
        result = budget.estimate(1e308, 1)
        self.assertFalse(result['fits_planning_budget'])
        self.assertGreater(result['gameplay_egress_gb'], 0)
        json.dumps(result, allow_nan=False)
        for rate, hours in ((5e-324, 1), (1e-308, 1), (1e308, 1e308), (1, 5e-324)):
            with self.subTest(rate=rate, hours=hours), self.assertRaises(ValueError):
                budget.estimate(rate, hours)


if __name__ == '__main__':
    unittest.main()
