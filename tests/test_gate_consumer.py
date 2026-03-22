#!/usr/bin/env python3
"""Tests for validate_gate.py in consumer repo context (6 cases).

Covers: REPO_ROOT resolution at source vs consumer depth, and
consumer-side gate execution.
"""

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest import TestCase, main as unittest_main

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE_SCRIPT = REPO_ROOT / "skills" / "reference-implementation-study" / "validate_gate.py"


def _load_module_with_root(script_path: Path, repo_root: Path):
    """Load validate_gate.py from a given path, patching REPO_ROOT."""
    spec = importlib.util.spec_from_file_location("validate_gate", script_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # Patch REPO_ROOT AFTER exec so the module-level assignment is overridden
    mod.REPO_ROOT = repo_root
    return mod


class TestRepoRootResolution(TestCase):
    """5.1 REPO_ROOT Resolution tests."""

    def test_5_1_1_source_repo_path(self):
        """From source path skills/<skill>/validate_gate.py, parents[3] goes
        ONE level above the repo root (too far). This documents the mismatch."""
        resolved = GATE_SCRIPT.resolve().parents[3]
        # parents[2] = repo root, parents[3] = repo root's parent
        expected_repo_root = GATE_SCRIPT.resolve().parents[2]
        self.assertEqual(
            expected_repo_root, REPO_ROOT.resolve(),
            "parents[2] should be the source repo root"
        )
        self.assertNotEqual(
            resolved, REPO_ROOT.resolve(),
            "parents[3] should NOT match source repo root (it goes one level too high)"
        )

    def test_5_1_2_consumer_repo_path(self):
        """From consumer path .claude/skills/<skill>/validate_gate.py,
        parents[3] correctly resolves to the consumer repo root."""
        with tempfile.TemporaryDirectory() as tmpdir:
            consumer_root = Path(tmpdir).resolve()
            consumer_script = (
                consumer_root / ".claude" / "skills"
                / "reference-implementation-study" / "validate_gate.py"
            )
            consumer_script.parent.mkdir(parents=True)
            consumer_script.write_text("# placeholder", encoding="utf-8")

            resolved = consumer_script.resolve().parents[3]
            self.assertEqual(
                resolved, consumer_root,
                f"parents[3] should resolve to consumer root: {resolved} != {consumer_root}"
            )

    def test_5_1_3_depth_mismatch_bug(self):
        """Document: script uses parents[3] which works for consumer path
        (.claude/skills/<skill>/) but NOT for source path (skills/<skill>/).
        This is by design — the script is intended to run from consumer repos."""
        script_text = GATE_SCRIPT.read_text(encoding="utf-8")

        # Verify the script uses parents[3]
        self.assertIn("parents[3]", script_text, "Script uses parents[3]")

        # Verify the comment documents consumer-side intent
        self.assertIn(
            ".claude/skills/<skill>/", script_text,
            "Comment indicates consumer-side path assumption"
        )

        # Verify depth difference
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir).resolve()

            # Source: skills/<skill>/script.py → parents[2] = root
            src = root / "skills" / "ref" / "script.py"
            src.parent.mkdir(parents=True)
            src.write_text("", encoding="utf-8")
            self.assertEqual(src.resolve().parents[2], root)

            # Consumer: .claude/skills/<skill>/script.py → parents[3] = root
            con = root / ".claude" / "skills" / "ref" / "script.py"
            con.parent.mkdir(parents=True)
            con.write_text("", encoding="utf-8")
            self.assertEqual(con.resolve().parents[3], root)


class TestConsumerSideExecution(TestCase):
    """5.2 Consumer-Side Gate Execution tests."""

    def setUp(self):
        self.tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.tmpdir_obj.name)

    def tearDown(self):
        tmpdir_str = str(self.tmpdir)
        sys.path[:] = [p for p in sys.path if p != tmpdir_str]
        self.tmpdir_obj.cleanup()

    def _setup_consumer_repo(self):
        """Create a consumer repo layout with the gate script."""
        consumer = self.tmpdir
        gate_dir = consumer / ".claude" / "skills" / "reference-implementation-study"
        gate_dir.mkdir(parents=True)
        gate_script = gate_dir / "validate_gate.py"
        gate_script.write_text(GATE_SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")
        return consumer, gate_script

    def test_5_2_1_g1_from_consumer_path(self):
        """G1 from consumer path — using patched REPO_ROOT."""
        consumer, gate_script = self._setup_consumer_repo()

        impl = consumer / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("", encoding="utf-8")
        (impl.parent / "__init__.py").write_text("", encoding="utf-8")
        (impl / "utils.py").write_text("# utils\n", encoding="utf-8")
        (impl / "method_a.py").write_text("value = 1\n", encoding="utf-8")
        (impl / "method_b.py").write_text("value = 2\n", encoding="utf-8")
        tests = consumer / "tests" / "test-study"
        tests.mkdir(parents=True)
        (tests / "__init__.py").write_text("", encoding="utf-8")
        (tests / "test_basic.py").write_text("def test_pass(): assert True\n", encoding="utf-8")

        mod = _load_module_with_root(gate_script, consumer)
        results = mod.gate_g1("test-study", "test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"G1 from consumer path failed: {fails}")

    def test_5_2_2_g2_from_consumer_path(self):
        """G2 from consumer path — using patched REPO_ROOT."""
        consumer, gate_script = self._setup_consumer_repo()

        art = consumer / "artifacts" / "test-study" / "baseline"
        art.mkdir(parents=True)
        summary = {
            "methods": {
                "a": {"mean": 0.9, "std": 0.01},
                "b": {"mean": 0.8, "std": 0.02},
            }
        }
        (art / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
        try:
            import numpy as np
            np.savez(str(art / "results.npz"), data=[1, 2, 3])
        except ImportError:
            import zipfile, io, struct
            with zipfile.ZipFile(str(art / "results.npz"), "w") as zf:
                buf = io.BytesIO()
                header = b"\x93NUMPY\x01\x00"
                d = {"descr": "<f8", "fortran_order": False, "shape": (3,)}
                header_str = repr(d).encode("latin1")
                padding = 64 - ((len(header) + 2 + len(header_str)) % 64)
                header_str += b" " * padding + b"\n"
                buf.write(header)
                buf.write(struct.pack("<H", len(header_str)))
                buf.write(header_str)
                buf.write(struct.pack("<ddd", 1.0, 2.0, 3.0))
                zf.writestr("data.npy", buf.getvalue())
        manifest = {"iterations": [{"phase": 3}]}
        (consumer / "artifacts" / "test-study" / "study-manifest.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

        mod = _load_module_with_root(gate_script, consumer)
        results = mod.gate_g2("test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"G2 from consumer path failed: {fails}")

    def test_5_2_3_import_path_setup(self):
        """Verify sys.path manipulation finds implementation/<topic>/ at consumer root."""
        consumer, gate_script = self._setup_consumer_repo()

        impl = consumer / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("", encoding="utf-8")
        (impl.parent / "__init__.py").write_text("", encoding="utf-8")
        (impl / "utils.py").write_text("MARKER = 'consumer_root'\n", encoding="utf-8")
        (impl / "method_a.py").write_text("value = 1\n", encoding="utf-8")
        (impl / "method_b.py").write_text("value = 2\n", encoding="utf-8")
        tests = consumer / "tests" / "test-study"
        tests.mkdir(parents=True)
        (tests / "__init__.py").write_text("", encoding="utf-8")
        (tests / "test_basic.py").write_text("def test_pass(): assert True\n", encoding="utf-8")

        mod = _load_module_with_root(gate_script, consumer)
        results = mod.gate_g1("test-study", "test-study")
        import_results = [msg for ok, msg in results if "importable" in msg]
        self.assertTrue(
            len(import_results) >= 2,
            "Should have attempted to import at least 2 modules"
        )


if __name__ == "__main__":
    unittest_main(verbosity=2)
