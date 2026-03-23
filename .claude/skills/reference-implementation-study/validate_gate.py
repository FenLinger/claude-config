#!/usr/bin/env python3
"""Quality-gate validator for the reference-implementation-study skill.

Usage:
    python validate_gate.py <study-name> <gate> <topic>

Gates:
    G1  Phase 2 → 3  (Implementation → Baseline)
    G2  Phase 3 → 4  (Baseline → Sensitivity)
    G3  Phase 4 → 5  (Sensitivity → Precision)
    G4  Phase 5 → 6  (Precision → Report)

Exit codes:
    0  PASS — all checks succeeded
    1  FAIL — one or more checks failed (details printed to stderr)
    2  Usage error
"""

from __future__ import annotations

import importlib
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]  # .claude/skills/<skill>/ → repo root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _check(ok: bool, msg: str, results: list[tuple[bool, str]]) -> None:
    results.append((ok, msg))


def _find_candidate_modules(study: str, topic: str) -> list[str]:
    """Return importable module names under implementation/<topic>/ (excluding utils)."""
    impl_dir = REPO_ROOT / "implementation" / topic
    if not impl_dir.is_dir():
        return []
    return [
        p.stem
        for p in impl_dir.glob("*.py")
        if p.stem not in ("__init__", "utils", "__pycache__")
    ]


def _json_loadable(path: Path) -> tuple[bool, dict | list | None]:
    try:
        with open(path) as f:
            data = json.load(f)
        return True, data
    except (json.JSONDecodeError, OSError):
        return False, None


def _npz_loadable(path: Path) -> bool:
    try:
        import numpy as np
        np.load(path, allow_pickle=False)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Gate validators
# ---------------------------------------------------------------------------

def gate_g1(study: str, topic: str) -> list[tuple[bool, str]]:
    """G1: Implementation → Baseline."""
    results: list[tuple[bool, str]] = []

    # Check implementation/<topic>/ exists
    impl_dir = REPO_ROOT / "implementation" / topic
    _check(impl_dir.is_dir(), f"implementation/{topic}/ directory exists", results)

    # Check utils.py exists
    _check(
        (impl_dir / "utils.py").is_file(),
        f"implementation/{topic}/utils.py exists",
        results,
    )

    # Check candidate modules are importable
    modules = _find_candidate_modules(study, topic)
    _check(len(modules) >= 2, f"At least 2 candidate modules found ({len(modules)})", results)

    sys.path.insert(0, str(REPO_ROOT))
    for mod_name in modules:
        try:
            importlib.import_module(f"implementation.{topic}.{mod_name}")
            _check(True, f"implementation.{topic}.{mod_name} importable", results)
        except Exception as exc:
            _check(False, f"implementation.{topic}.{mod_name} import failed: {exc}", results)
    sys.path.pop(0)

    # Check tests/<topic>/ exists
    tests_dir = REPO_ROOT / "tests" / topic
    _check(tests_dir.is_dir(), f"tests/{topic}/ directory exists", results)

    # Run pytest
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", str(tests_dir), "-v", "--tb=short"],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    _check(
        proc.returncode == 0,
        f"pytest tests/{topic}/ passes (rc={proc.returncode})",
        results,
    )
    if proc.returncode != 0:
        # Append abbreviated output for diagnostics
        for line in proc.stdout.splitlines()[-20:]:
            results.append((False, f"  pytest: {line}"))

    return results


def gate_g2(study: str) -> list[tuple[bool, str]]:
    """G2: Baseline → Sensitivity."""
    results: list[tuple[bool, str]] = []
    base = REPO_ROOT / "artifacts" / study / "baseline"

    # summary.json
    summary_path = base / "summary.json"
    ok, data = _json_loadable(summary_path)
    _check(ok, f"{summary_path.relative_to(REPO_ROOT)} is valid JSON", results)

    if ok and isinstance(data, dict):
        # Check metrics present
        methods = data.get("methods") or data.get("results") or {}
        _check(
            len(methods) >= 2,
            f"summary.json contains >= 2 methods ({len(methods)})",
            results,
        )
        # Check aggregated statistics present
        has_stats = any(
            "mean" in str(v) or "std" in str(v)
            for v in (methods.values() if isinstance(methods, dict) else methods)
        )
        _check(has_stats, "summary.json contains aggregated statistics (mean/std)", results)

    # .npz loadable
    npz_files = list(base.glob("*.npz"))
    _check(len(npz_files) >= 1, f"At least one .npz in baseline/ ({len(npz_files)})", results)
    for npz in npz_files:
        _check(
            _npz_loadable(npz),
            f"{npz.name} is loadable",
            results,
        )

    # manifest updated
    manifest_path = REPO_ROOT / "artifacts" / study / "study-manifest.json"
    mok, mdata = _json_loadable(manifest_path)
    _check(mok, "study-manifest.json exists and is valid JSON", results)
    if mok and isinstance(mdata, dict):
        iters = mdata.get("iterations", [])
        phase3 = [i for i in iters if i.get("phase") == 3]
        _check(len(phase3) >= 1, "study-manifest.json has Phase 3 entry", results)

    return results


def gate_g3(study: str) -> list[tuple[bool, str]]:
    """G3: Sensitivity → Precision."""
    results: list[tuple[bool, str]] = []
    art_dir = REPO_ROOT / "artifacts" / study

    # Look for sweep artifacts (any subdir that isn't baseline or precision)
    sweep_dirs = [
        d for d in art_dir.iterdir()
        if d.is_dir() and d.name not in ("baseline", "precision")
    ]
    _check(
        len(sweep_dirs) >= 1,
        f"At least one sweep artifact directory ({len(sweep_dirs)})",
        results,
    )

    for sd in sweep_dirs:
        jsons = list(sd.glob("*.json"))
        _check(
            len(jsons) >= 1,
            f"{sd.name}/ contains at least one .json summary",
            results,
        )

    # manifest updated
    manifest_path = art_dir / "study-manifest.json"
    mok, mdata = _json_loadable(manifest_path)
    _check(mok, "study-manifest.json exists and is valid JSON", results)
    if mok and isinstance(mdata, dict):
        iters = mdata.get("iterations", [])
        phase4 = [i for i in iters if i.get("phase") == 4]
        _check(len(phase4) >= 1, "study-manifest.json has Phase 4 entry", results)

    return results


def gate_g4(study: str) -> list[tuple[bool, str]]:
    """G4: Precision → Report."""
    results: list[tuple[bool, str]] = []
    prec_dir = REPO_ROOT / "artifacts" / study / "precision"

    _check(prec_dir.is_dir(), "artifacts/<study>/precision/ exists", results)

    if prec_dir.is_dir():
        npz_files = list(prec_dir.glob("*.npz"))
        _check(
            len(npz_files) >= 1,
            f"At least one .npz in precision/ ({len(npz_files)})",
            results,
        )
        for npz in npz_files:
            _check(_npz_loadable(npz), f"{npz.name} is loadable", results)

    # manifest updated
    manifest_path = REPO_ROOT / "artifacts" / study / "study-manifest.json"
    mok, mdata = _json_loadable(manifest_path)
    _check(mok, "study-manifest.json exists and is valid JSON", results)
    if mok and isinstance(mdata, dict):
        iters = mdata.get("iterations", [])
        phase5 = [i for i in iters if i.get("phase") == 5]
        _check(len(phase5) >= 1, "study-manifest.json has Phase 5 entry", results)

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

GATES = {
    "G1": gate_g1,
    "G2": gate_g2,
    "G3": gate_g3,
    "G4": gate_g4,
}


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[2].upper() not in GATES:
        print(f"Usage: {sys.argv[0]} <study-name> <G1|G2|G3|G4> [<topic>]", file=sys.stderr)
        return 2

    study = sys.argv[1]
    gate = sys.argv[2].upper()
    topic = sys.argv[3] if len(sys.argv) > 3 else study

    gate_fn = GATES[gate]
    # G1 requires topic; G2–G4 only use study-namespaced artifact paths
    if gate == "G1":
        results = gate_fn(study, topic)
    else:
        results = gate_fn(study)

    passed = sum(1 for ok, _ in results if ok)
    failed = sum(1 for ok, _ in results if not ok)

    print(f"\n{'=' * 60}")
    print(f"  Gate {gate} — study: {study}")
    print(f"{'=' * 60}\n")

    for ok, msg in results:
        status = "PASS" if ok else "FAIL"
        marker = "  [+]" if ok else "  [-]"
        print(f"{marker} {status}: {msg}")

    print(f"\n{'=' * 60}")
    if failed == 0:
        print(f"  GATE {gate}: PASS  ({passed}/{passed} checks)")
        print(f"{'=' * 60}\n")
        return 0
    else:
        print(f"  GATE {gate}: FAIL  ({passed} passed, {failed} failed)")
        print(f"{'=' * 60}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
