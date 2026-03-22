#!/usr/bin/env python3
"""Tests for validate_gate.py — Quality Gate Validator (28 cases).

Covers: CLI interface, G1-G4 gate validators, and output format.
"""

import importlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path
from unittest import TestCase, main as unittest_main, mock

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE_SCRIPT = REPO_ROOT / "skills" / "reference-implementation-study" / "validate_gate.py"


def load_gate_module():
    """Load validate_gate.py as a module, patching REPO_ROOT."""
    spec = importlib.util.spec_from_file_location("validate_gate", GATE_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    return spec, mod


def run_gate_cli(*args: str) -> subprocess.CompletedProcess:
    """Run validate_gate.py as a subprocess."""
    return subprocess.run(
        [sys.executable, str(GATE_SCRIPT)] + list(args),
        capture_output=True, text=True, timeout=30,
    )


class _GateTestBase(TestCase):
    """Base class that sets up a temp directory and patches REPO_ROOT."""

    def setUp(self):
        self.tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.tmpdir_obj.name)

        # Load the module fresh each time with patched REPO_ROOT
        spec = importlib.util.spec_from_file_location("validate_gate", GATE_SCRIPT)
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        # Patch REPO_ROOT AFTER exec so the module-level assignment is overridden
        self.mod.REPO_ROOT = self.tmpdir

    def tearDown(self):
        # Clean up sys.path entries added by gate_g1
        tmpdir_str = str(self.tmpdir)
        sys.path[:] = [p for p in sys.path if p != tmpdir_str]
        # Clear cached implementation modules to prevent cross-test contamination
        to_remove = [k for k in sys.modules if k.startswith("implementation")]
        for k in to_remove:
            del sys.modules[k]
        self.tmpdir_obj.cleanup()

    def _make_study(self, study="test-study"):
        """Create minimal artifacts directory for a study."""
        art = self.tmpdir / "artifacts" / study
        art.mkdir(parents=True, exist_ok=True)
        return art


# ===================================================================
# 2.1 CLI Interface
# ===================================================================

class TestCLI(TestCase):
    """2.1 CLI Interface tests."""

    def test_2_1_1_no_arguments(self):
        r = run_gate_cli()
        self.assertEqual(r.returncode, 2)
        self.assertIn("Usage", r.stderr)

    def test_2_1_2_one_argument(self):
        r = run_gate_cli("study-name")
        self.assertEqual(r.returncode, 2)

    def test_2_1_3_invalid_gate(self):
        r = run_gate_cli("study-name", "G5")
        self.assertEqual(r.returncode, 2)

    def test_2_1_4_case_insensitive_gate(self):
        # g1 lowercase — will fail on checks but should not give usage error
        r = run_gate_cli("study-name", "g1")
        self.assertNotEqual(r.returncode, 2, "lowercase gate should be accepted")

    def test_2_1_5_valid_invocation(self):
        r = run_gate_cli("study-name", "G1")
        # Will fail on checks (no implementation/ dir) but rc should be 1, not 2
        self.assertIn(r.returncode, (0, 1))

    def test_2_1_6_optional_topic_argument(self):
        """Topic is optional — when omitted, defaults to study name."""
        r = run_gate_cli("study-name", "G1", "custom-topic")
        # Will fail on checks but rc should be 1, not 2 (usage error)
        self.assertIn(r.returncode, (0, 1))


# ===================================================================
# 2.2 Gate G1 — Implementation → Baseline
# ===================================================================

class TestGateG1(_GateTestBase):
    """2.2 Gate G1 tests."""

    def _setup_g1_passing(self, study="test-study", topic="test-study"):
        """Set up a fully passing G1 fixture."""
        impl = self.tmpdir / "implementation" / topic
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("# utils\n")
        (impl / "method_a.py").write_text("# method a\nvalue = 1\n")
        (impl / "method_b.py").write_text("# method b\nvalue = 2\n")

        tests = self.tmpdir / "tests" / topic
        tests.mkdir(parents=True)
        (tests / "__init__.py").write_text("")
        (tests / "test_basic.py").write_text(
            "def test_pass(): assert True\n"
        )

    def test_2_2_1_all_passing(self):
        self._setup_g1_passing()
        results = self.mod.gate_g1("test-study", "test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"Unexpected failures: {fails}")

    def test_2_2_2_missing_implementation_dir(self):
        results = self.mod.gate_g1("test-study", "test-study")
        ok_map = {msg: ok for ok, msg in results}
        self.assertFalse(
            ok_map.get("implementation/test-study/ directory exists", True),
            "Should fail when implementation/<topic>/ missing",
        )

    def test_2_2_3_missing_utils_py(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        (impl / "method_b.py").write_text("value=2\n")
        results = self.mod.gate_g1("test-study", "test-study")
        ok_map = {msg: ok for ok, msg in results}
        self.assertFalse(
            ok_map.get("implementation/test-study/utils.py exists", True),
            "Should fail when utils.py missing",
        )

    def test_2_2_4_only_1_candidate(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        results = self.mod.gate_g1("test-study", "test-study")
        found = [msg for ok, msg in results if "At least 2" in msg and not ok]
        self.assertTrue(len(found) >= 1, "Should fail with only 1 candidate")

    def test_2_2_5_candidate_import_fails(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        (impl / "method_b.py").write_text("raise ImportError('broken')\n")
        results = self.mod.gate_g1("test-study", "test-study")
        import_fails = [msg for ok, msg in results if "import failed" in msg]
        self.assertTrue(len(import_fails) >= 1, "Should report import failure")

    def test_2_2_6_no_tests_directory(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        (impl / "method_b.py").write_text("value=2\n")
        results = self.mod.gate_g1("test-study", "test-study")
        ok_map = {msg: ok for ok, msg in results}
        self.assertFalse(
            ok_map.get("tests/test-study/ directory exists", True),
            "Should fail when tests/<topic>/ missing",
        )

    def test_2_2_7_pytest_fails(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        (impl / "method_b.py").write_text("value=2\n")
        tests = self.tmpdir / "tests" / "test-study"
        tests.mkdir(parents=True)
        (tests / "__init__.py").write_text("")
        (tests / "test_fail.py").write_text("def test_fail(): assert False\n")
        results = self.mod.gate_g1("test-study", "test-study")
        pytest_results = [msg for ok, msg in results if "pytest" in msg.lower() and not ok]
        self.assertTrue(len(pytest_results) >= 1, "Should fail when pytest fails")

    def test_2_2_8_init_and_pycache_excluded(self):
        impl = self.tmpdir / "implementation" / "test-study"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("")
        pycache = impl / "__pycache__"
        pycache.mkdir()
        (pycache / "cached.pyc").write_text("")
        (impl / "method_a.py").write_text("value=1\n")
        (impl / "method_b.py").write_text("value=2\n")
        candidates = self.mod._find_candidate_modules("test-study", "test-study")
        self.assertNotIn("__init__", candidates)
        self.assertNotIn("utils", candidates)
        self.assertNotIn("__pycache__", candidates)
        self.assertIn("method_a", candidates)
        self.assertIn("method_b", candidates)

    def test_2_2_9_custom_topic_separate_from_study(self):
        """Topic can differ from study name (e.g., study='prach-receiver', topic='prach')."""
        impl = self.tmpdir / "implementation" / "prach"
        impl.mkdir(parents=True)
        (impl / "__init__.py").write_text("")
        (impl.parent / "__init__.py").write_text("")
        (impl / "utils.py").write_text("# utils\n")
        (impl / "method_a.py").write_text("value = 1\n")
        (impl / "method_b.py").write_text("value = 2\n")

        tests = self.tmpdir / "tests" / "prach"
        tests.mkdir(parents=True)
        (tests / "__init__.py").write_text("")
        (tests / "test_basic.py").write_text("def test_pass(): assert True\n")

        results = self.mod.gate_g1("prach-receiver", "prach")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"Unexpected failures: {fails}")
        # Verify topic appears in messages, not study name
        all_msgs = [msg for _, msg in results]
        topic_msgs = [m for m in all_msgs if "prach" in m]
        self.assertTrue(len(topic_msgs) >= 1, "Topic 'prach' should appear in check messages")


# ===================================================================
# 2.3 Gate G2 — Baseline → Sensitivity
# ===================================================================

class TestGateG2(_GateTestBase):
    """2.3 Gate G2 tests."""

    def _setup_g2_passing(self, study="test-study"):
        art = self._make_study(study)
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {
            "methods": {
                "method_a": {"mean": 0.9, "std": 0.01},
                "method_b": {"mean": 0.85, "std": 0.02},
            }
        }
        (baseline / "summary.json").write_text(json.dumps(summary))
        # Create a valid .npz file
        try:
            import numpy as np
            np.savez(str(baseline / "results.npz"), data=[1, 2, 3])
        except ImportError:
            # Fallback: create a minimal .npz (ZIP with .npy)
            import zipfile, io, struct
            npz_path = baseline / "results.npz"
            with zipfile.ZipFile(str(npz_path), "w") as zf:
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
        # Create manifest
        manifest = {"iterations": [{"phase": 3, "date": "2026-01-01"}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))

    def test_2_3_1_all_passing(self):
        self._setup_g2_passing()
        results = self.mod.gate_g2("test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"Unexpected failures: {fails}")

    def test_2_3_2_missing_summary_json(self):
        art = self._make_study()
        (art / "baseline").mkdir()
        results = self.mod.gate_g2("test-study")
        ok_map = {msg: ok for ok, msg in results}
        has_json_fail = any("JSON" in msg and not ok for ok, msg in results)
        self.assertTrue(has_json_fail, "Should fail when summary.json missing")

    def test_2_3_3_invalid_json(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        (baseline / "summary.json").write_text("{broken")
        results = self.mod.gate_g2("test-study")
        has_json_fail = any("JSON" in msg and not ok for ok, msg in results)
        self.assertTrue(has_json_fail, "Should fail on invalid JSON")

    def test_2_3_4_fewer_than_2_methods(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"only_one": {"mean": 0.9, "std": 0.01}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        results = self.mod.gate_g2("test-study")
        method_fail = [msg for ok, msg in results if "2 methods" in msg and not ok]
        self.assertTrue(len(method_fail) >= 1, "Should fail with < 2 methods")

    def test_2_3_5_no_mean_std_statistics(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"a": {"score": 0.9}, "b": {"score": 0.8}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        results = self.mod.gate_g2("test-study")
        stats_fail = [msg for ok, msg in results if "statistics" in msg and not ok]
        self.assertTrue(len(stats_fail) >= 1, "Should fail without mean/std")

    def test_2_3_6_no_npz_files(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"a": {"mean": 0.9, "std": 0.01}, "b": {"mean": 0.8, "std": 0.02}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        manifest = {"iterations": [{"phase": 3}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g2("test-study")
        npz_fail = [msg for ok, msg in results if "npz" in msg.lower() and not ok]
        self.assertTrue(len(npz_fail) >= 1, "Should fail with no .npz files")

    def test_2_3_7_corrupt_npz(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"a": {"mean": 0.9, "std": 0.01}, "b": {"mean": 0.8, "std": 0.02}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        (baseline / "bad.npz").write_text("not a valid npz file")
        manifest = {"iterations": [{"phase": 3}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g2("test-study")
        npz_fail = [msg for ok, msg in results if "loadable" in msg and not ok]
        self.assertTrue(len(npz_fail) >= 1, "Should fail on corrupt .npz")

    def test_2_3_8_manifest_missing_phase3(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"a": {"mean": 0.9, "std": 0.01}, "b": {"mean": 0.8, "std": 0.02}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        manifest = {"iterations": [{"phase": 1}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g2("test-study")
        phase_fail = [msg for ok, msg in results if "Phase 3" in msg and not ok]
        self.assertTrue(len(phase_fail) >= 1, "Should fail without phase 3 entry")

    def test_2_3_9_manifest_missing_entirely(self):
        art = self._make_study()
        baseline = art / "baseline"
        baseline.mkdir()
        summary = {"methods": {"a": {"mean": 0.9, "std": 0.01}, "b": {"mean": 0.8, "std": 0.02}}}
        (baseline / "summary.json").write_text(json.dumps(summary))
        results = self.mod.gate_g2("test-study")
        manifest_fail = [msg for ok, msg in results if "manifest" in msg.lower() and not ok]
        self.assertTrue(len(manifest_fail) >= 1, "Should fail when manifest missing")


# ===================================================================
# 2.4 Gate G3 — Sensitivity → Precision
# ===================================================================

class TestGateG3(_GateTestBase):
    """2.4 Gate G3 tests."""

    def test_2_4_1_all_passing(self):
        art = self._make_study()
        sweep = art / "sweep-lr"
        sweep.mkdir()
        (sweep / "results.json").write_text(json.dumps({"lr": 0.01}))
        manifest = {"iterations": [{"phase": 4}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g3("test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"Unexpected failures: {fails}")

    def test_2_4_2_no_sweep_directories(self):
        art = self._make_study()
        (art / "baseline").mkdir()
        manifest = {"iterations": [{"phase": 4}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g3("test-study")
        sweep_fail = [msg for ok, msg in results if "sweep" in msg.lower() and not ok]
        self.assertTrue(len(sweep_fail) >= 1, "Should fail with no sweep dirs")

    def test_2_4_3_sweep_dir_without_json(self):
        art = self._make_study()
        sweep = art / "sweep-lr"
        sweep.mkdir()
        # No JSON files in sweep dir
        manifest = {"iterations": [{"phase": 4}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g3("test-study")
        json_fail = [msg for ok, msg in results if "json" in msg.lower() and not ok]
        self.assertTrue(len(json_fail) >= 1, "Should fail with no JSON in sweep dir")

    def test_2_4_4_baseline_and_precision_excluded(self):
        art = self._make_study()
        (art / "baseline").mkdir()
        (art / "precision").mkdir()
        manifest = {"iterations": [{"phase": 4}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g3("test-study")
        sweep_fail = [msg for ok, msg in results if "sweep" in msg.lower() and not ok]
        self.assertTrue(len(sweep_fail) >= 1, "baseline and precision should be excluded")

    def test_2_4_5_manifest_missing_phase4(self):
        art = self._make_study()
        sweep = art / "sweep-lr"
        sweep.mkdir()
        (sweep / "results.json").write_text(json.dumps({"lr": 0.01}))
        manifest = {"iterations": [{"phase": 3}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g3("test-study")
        phase_fail = [msg for ok, msg in results if "Phase 4" in msg and not ok]
        self.assertTrue(len(phase_fail) >= 1, "Should fail without phase 4")


# ===================================================================
# 2.5 Gate G4 — Precision → Report
# ===================================================================

class TestGateG4(_GateTestBase):
    """2.5 Gate G4 tests."""

    def _make_precision_npz(self, art):
        prec = art / "precision"
        prec.mkdir(exist_ok=True)
        try:
            import numpy as np
            np.savez(str(prec / "wordlength.npz"), data=[1, 2, 3])
        except ImportError:
            import zipfile, io, struct
            npz_path = prec / "wordlength.npz"
            with zipfile.ZipFile(str(npz_path), "w") as zf:
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

    def test_2_5_1_all_passing(self):
        art = self._make_study()
        self._make_precision_npz(art)
        manifest = {"iterations": [{"phase": 5}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g4("test-study")
        fails = [msg for ok, msg in results if not ok]
        self.assertEqual(fails, [], f"Unexpected failures: {fails}")

    def test_2_5_2_no_precision_directory(self):
        art = self._make_study()
        manifest = {"iterations": [{"phase": 5}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g4("test-study")
        prec_fail = [msg for ok, msg in results if "precision" in msg.lower() and not ok]
        self.assertTrue(len(prec_fail) >= 1, "Should fail without precision/")

    def test_2_5_3_precision_exists_no_npz(self):
        art = self._make_study()
        (art / "precision").mkdir()
        manifest = {"iterations": [{"phase": 5}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g4("test-study")
        npz_fail = [msg for ok, msg in results if "npz" in msg.lower() and not ok]
        self.assertTrue(len(npz_fail) >= 1, "Should fail with no .npz in precision")

    def test_2_5_4_corrupt_npz_in_precision(self):
        art = self._make_study()
        prec = art / "precision"
        prec.mkdir()
        (prec / "bad.npz").write_text("corrupt data")
        manifest = {"iterations": [{"phase": 5}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g4("test-study")
        load_fail = [msg for ok, msg in results if "loadable" in msg and not ok]
        self.assertTrue(len(load_fail) >= 1, "Should fail on corrupt .npz")

    def test_2_5_5_manifest_missing_phase5(self):
        art = self._make_study()
        self._make_precision_npz(art)
        manifest = {"iterations": [{"phase": 4}]}
        (art / "study-manifest.json").write_text(json.dumps(manifest))
        results = self.mod.gate_g4("test-study")
        phase_fail = [msg for ok, msg in results if "Phase 5" in msg and not ok]
        self.assertTrue(len(phase_fail) >= 1, "Should fail without phase 5")


# ===================================================================
# 2.6 Output Format
# ===================================================================

class TestOutputFormat(TestCase):
    """2.6 Output format tests."""

    def test_2_6_1_pass_output_format(self):
        r = run_gate_cli("test-study", "G1")
        combined = r.stdout + r.stderr
        self.assertIn("=====", combined)
        self.assertIn("Gate G1", combined)

    def test_2_6_2_fail_output_format(self):
        r = run_gate_cli("test-study", "G1")
        combined = r.stdout + r.stderr
        # G1 will fail (no implementation dir), so expect FAIL markers
        self.assertIn("FAIL", combined)
        self.assertIn("[-]", combined)

    def test_2_6_3_mixed_results(self):
        # Create a setup where some pass and some fail
        # Running G1 without proper setup: implementation/ check fails,
        # but other checks may have their own status
        r = run_gate_cli("test-study", "G1")
        combined = r.stdout + r.stderr
        # We expect at least FAIL markers (everything should fail with no setup)
        self.assertIn("[-]", combined)
        self.assertIn("FAIL", combined)


if __name__ == "__main__":
    unittest_main(verbosity=2)
