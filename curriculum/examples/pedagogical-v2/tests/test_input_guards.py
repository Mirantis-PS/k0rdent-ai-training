"""CPU-only CLI guard checks; do not test or simulate NCCL/GPU execution."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("two_worker", Path(__file__).resolve().parents[1] / "two-worker.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GuardTests(unittest.TestCase):
    def parse(self, world, *arguments):
        with patch.dict(os.environ, {"WORLD_SIZE": str(world)}), patch("sys.argv", ["two-worker.py", *arguments]):
            return MODULE.parse_args()

    def rejected(self, world, *arguments):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            self.parse(world, *arguments)
        self.assertEqual(error.exception.code, 2)

    def test_valid_baseline_and_pair(self):
        for world in (1, 2):
            args, actual = self.parse(world)
            self.assertEqual(actual, world)
            self.assertEqual(args.global_batch, 64)

    def test_requires_supported_world(self):
        for world in (0, 3, -1):
            self.rejected(world)

    def test_training_needs_two_or_more_steps(self):
        for steps in (0, 1, 101):
            self.rejected(2, "--steps", str(steps))

    def test_global_batch_splits_evenly(self):
        self.rejected(2, "--global-batch", "63")

    def test_global_batch_is_bounded(self):
        for batch in (0, -2, 1026):
            self.rejected(2, "--global-batch", str(batch))


if __name__ == "__main__":
    unittest.main()
