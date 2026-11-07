import json
from pathlib import Path
import tempfile
import unittest
import probe_openrouter as probe


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.previous = probe.ROOT
        self.directory = tempfile.TemporaryDirectory()
        probe.ROOT = Path(self.directory.name)

    def tearDown(self):
        probe.ROOT = self.previous
        self.directory.cleanup()

    def test_reservations_survive_restart_and_nonfinite_cost_is_not_accepted(self):
        with probe.ProbeBudget() as budget:
            first = budget.reserve()
            second = budget.reserve()
            budget.settle(first, .003)
            budget.settle(second, float('inf'))
        with probe.ProbeBudget() as restarted:
            self.assertAlmostEqual(sum(row.get('actual', row['reserved']) for row in restarted.ledger['entries']), .253)
            for _ in range(6): restarted.reserve()
            with self.assertRaises(SystemExit): restarted.reserve()

    def test_shared_lock_refuses_another_writer(self):
        with probe.ProbeBudget():
            with self.assertRaises(SystemExit):
                with probe.ProbeBudget(): pass
        self.assertFalse((probe.ROOT / 'runs/budget.lock').exists())

    def test_historical_probe_charges_seed_once(self):
        folder = probe.ROOT / 'runs/feasibility'; folder.mkdir(parents=True)
        (folder / 'old-summary.json').write_text(json.dumps({'results': [{'usage': {'cost': .002}}, {'usage': None}]}))
        for _ in range(2):
            with probe.ProbeBudget() as budget:
                self.assertEqual(len(budget.ledger['entries']), 1)
                self.assertEqual(budget.ledger['entries'][0]['actual'], .002)


if __name__ == '__main__': unittest.main()
