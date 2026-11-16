import argparse
import json
import math
import statistics
import sys
import time
from pathlib import Path


def percentile(values, fraction):
    xs = sorted(values)

    if not xs:
        return 0.0

    if len(xs) == 1:
        return xs[0]

    pos = (len(xs) - 1) * fraction
    lo = math.floor(pos)
    hi = math.ceil(pos)

    if lo == hi:
        return xs[lo]

    weight = pos - lo
    return (
        xs[lo] * (1.0 - weight)
        + xs[hi] * weight
    )


def flatten_summary(value):
    if value is None:
        return "<none>"

    if not isinstance(value, dict):
        return str(value)

    preferred = (
        "outcome",
        "decision",
        "reason",
        "reason_code",
        "status",
    )

    parts = []

    for key in preferred:
        if key in value:
            item = value[key]

            if isinstance(
                item,
                (str, int, float, bool)
            ) or item is None:
                parts.append(f"{key}={item}")

    if parts:
        return "; ".join(parts)

    for key in sorted(value):
        item = value[key]

        if isinstance(
            item,
            (str, int, float, bool)
        ) or item is None:
            parts.append(f"{key}={item}")

    return "; ".join(parts) if parts else "<object>"


def response_summary(response):
    if response is None:
        return "<not sent to runner>"

    parts = []

    if isinstance(response, dict):
        for key in (
            "outcome",
            "decision",
            "reason",
            "reason_code",
            "status",
        ):
            if key in response:
                parts.append(
                    f"{key}={response[key]}"
                )

        for container in (
            "result",
            "output",
            "response",
        ):
            nested = response.get(container)

            if isinstance(nested, dict):
                for key in (
                    "outcome",
                    "decision",
                    "reason",
                    "reason_code",
                    "status",
                ):
                    if key in nested:
                        parts.append(
                            f"{container}.{key}="
                            f"{nested[key]}"
                        )

    if parts:
        return "; ".join(parts)

    text = json.dumps(
        response,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )

    return (
        text
        if len(text) <= 360
        else text[:357] + "..."
    )


def stats(prefix, values):
    print(f"{prefix}_COUNT={len(values)}")

    if not values:
        return

    print(f"{prefix}_MIN_MS={min(values):.3f}")
    print(f"{prefix}_MAX_MS={max(values):.3f}")
    print(
        f"{prefix}_MEAN_MS="
        f"{statistics.fmean(values):.3f}"
    )
    print(
        f"{prefix}_MEDIAN_MS="
        f"{statistics.median(values):.3f}"
    )
    print(
        f"{prefix}_P95_MS="
        f"{percentile(values, 0.95):.3f}"
    )
    print(
        f"{prefix}_P99_MS="
        f"{percentile(values, 0.99):.3f}"
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--harness-dir",
        required=True,
    )
    parser.add_argument(
        "--vectors",
        required=True,
    )
    parser.add_argument(
        "--manifest",
        required=True,
    )
    parser.add_argument(
        "--runner",
        required=True,
    )

    args = parser.parse_args()

    harness_dir = Path(
        args.harness_dir
    ).resolve()

    vectors_dir = Path(
        args.vectors
    ).resolve()

    manifest_path = Path(
        args.manifest
    ).resolve()

    runner_path = Path(
        args.runner
    ).resolve()

    sys.path.insert(
        0,
        str(harness_dir),
    )

    import harness as base_harness
    import harness_runner as core

    class TimedTarget(core.RunnerTarget):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

            self.elapsed = {}
            self.responses = {}

        def evaluate(self, vector):
            test_id = vector["test_id"]

            start = time.perf_counter_ns()

            try:
                response = super().evaluate(vector)
                self.responses[test_id] = response
                return response

            finally:
                end = time.perf_counter_ns()

                self.elapsed[test_id] = (
                    end - start
                ) / 1_000_000.0

    class TimedHarness(core.RunnerHarness):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

            self.elapsed = {}

        def run_test(self, vector):
            test_id = vector["test_id"]

            start = time.perf_counter_ns()

            try:
                return super().run_test(vector)

            finally:
                end = time.perf_counter_ns()

                self.elapsed[test_id] = (
                    end - start
                ) / 1_000_000.0

    manifest = core.ConformanceManifest(
        manifest_path
    )

    print()
    print("=== MANIFEST VERIFICATION ===")
    print(f"SPEC_VERSION={manifest.spec_version}")
    print(f"PROFILE={manifest.profile}")
    print(f"VECTOR_SET={manifest.vector_set}")
    print(
        f"EXPECTED_DIGEST="
        f"{manifest.expected_digest}"
    )
    print(
        f"MANIFEST_TOTAL="
        f"{manifest.total_vectors}"
    )

    digest_ok = manifest.verify_vector_digest(
        vectors_dir
    )

    print(
        f"VECTOR_DIGEST_MATCH="
        f"{str(digest_ok).upper()}"
    )

    if not digest_ok:
        raise RuntimeError(
            "Canonical vector digest mismatch."
        )

    schemas = base_harness.load_schemas()

    key_loader = (
        base_harness.KeyLoader()
        if base_harness.HAS_CRYPTO
        else None
    )

    target = TimedTarget(
        runner_command=[str(runner_path)],
        timeout_ms=5000,
        verbose=True,
    )

    verifier = (
        core.protocol_v1_verifier.
        ProtocolV1ResponseVerifier(
            public_key=(
                key_loader.public_key
                if key_loader
                else None
            )
        )
    )

    harness = TimedHarness(
        target,
        verifier,
        schemas,
        manifest,
    )

    print()
    print("=== CANONICAL CORE-38 EXECUTION ===")

    suite_start = time.perf_counter_ns()

    try:
        target.start()

        summary = harness.run_all(
            vectors_dir
        )

    finally:
        target.stop()

    suite_end = time.perf_counter_ns()

    suite_ms = (
        suite_end - suite_start
    ) / 1_000_000.0

    results = {
        r.test_id: r
        for r in summary["results"]
    }

    files = sorted(
        vectors_dir.glob("*.json")
    )

    runner_times = []
    vector_times = []

    failure_ids = []

    print()
    print("=== CORE-38 FULL VECTOR REPORT ===")

    for index, path in enumerate(
        files,
        start=1,
    ):
        with path.open(
            "r",
            encoding="utf-8",
        ) as handle:
            loose = json.load(handle)

        test_id = loose.get(
            "test_id",
            path.stem,
        )

        description = loose.get(
            "description",
            "",
        )

        expected = flatten_summary(
            loose.get("expected")
        )

        result = results.get(test_id)

        passed = (
            result.passed
            if result is not None
            else False
        )

        if test_id in target.responses:
            observed = response_summary(
                target.responses[test_id]
            )

            runner_ms = target.elapsed[test_id]
            vector_ms = harness.elapsed[test_id]

            runner_times.append(runner_ms)
            vector_times.append(vector_ms)

            runner_text = (
                f"{runner_ms:.3f}"
            )

            vector_text = (
                f"{vector_ms:.3f}"
            )

            execution_path = "ADA_RUNNER"

        else:
            # Canonical duplicate-key rejection:
            # the vector is rejected before target.evaluate().
            start = time.perf_counter_ns()

            duplicate_ok = False

            try:
                with path.open(
                    "r",
                    encoding="utf-8",
                ) as handle:
                    json.load(
                        handle,
                        object_pairs_hook=
                            base_harness._reject_duplicates,
                    )

            except base_harness.DuplicateKeyError:
                duplicate_ok = (
                    loose.get("type") == "negative"
                    and
                    loose.get(
                        "expected",
                        {}
                    ).get("outcome") == "DENY"
                )

            end = time.perf_counter_ns()

            preflight_ms = (
                end - start
            ) / 1_000_000.0

            observed = (
                "duplicate_keys_rejected"
                if duplicate_ok
                else
                "preflight_rejection_failed"
            )

            runner_text = "N/A"
            vector_text = f"{preflight_ms:.3f}"

            vector_times.append(
                preflight_ms
            )

            execution_path = (
                "CANONICAL_HARNESS_PREFLIGHT"
            )

        status = (
            "PASS"
            if passed
            else
            "FAIL"
        )

        print()
        print(f"[{index:02d}/38] {test_id}")
        print(f"DESCRIPTION={description}")
        print(f"EXPECTED={expected}")
        print(f"OBSERVED={observed}")
        print(
            f"EXECUTION_PATH="
            f"{execution_path}"
        )
        print(
            f"TARGET_EVALUATE_MS="
            f"{runner_text}"
        )
        print(
            f"VECTOR_TOTAL_MS="
            f"{vector_text}"
        )
        print(f"RESULT={status}")

        if not passed:
            failure_ids.append(test_id)

            if result is not None:
                print(
                    "DETAILS="
                    + json.dumps(
                        result.details,
                        ensure_ascii=False,
                        sort_keys=True,
                        default=str,
                    )
                )

    print()
    print("=== CORE-38 AGGREGATES ===")

    print(
        f"CORE_TOTAL="
        f"{summary['total']}"
    )

    print(
        f"CORE_PASSED="
        f"{summary['passed']}"
    )

    print(
        f"CORE_FAILED="
        f"{summary['failed']}"
    )

    print(
        f"CORE_SUITE_WALL_MS="
        f"{suite_ms:.3f}"
    )

    print()
    stats(
        "CORE_TARGET_EVALUATE",
        runner_times,
    )

    print()
    stats(
        "CORE_VECTOR_TOTAL",
        vector_times,
    )

    print()
    print(
        f"CORE_ADA_RUNNER_VECTOR_COUNT="
        f"{len(runner_times)}"
    )

    print(
        f"CORE_PREFLIGHT_ONLY_VECTOR_COUNT="
        f"{38 - len(runner_times)}"
    )

    print(
        "TARGET_EVALUATE_DEFINITION="
        "wall time of canonical RunnerTarget.evaluate "
        "including request serialization/write, "
        "Ada runner response wait/read, JSON decode, "
        "and protocol checks"
    )

    print(
        "VECTOR_TOTAL_DEFINITION="
        "canonical run_test path: schema preflight + "
        "RunnerTarget.evaluate + canonical response verification; "
        "duplicate-key negative vector uses canonical "
        "pre-runner rejection path"
    )

    if manifest.total_vectors != 38:
        raise RuntimeError(
            "Manifest does not declare 38 vectors."
        )

    if summary["total"] != 38:
        raise RuntimeError(
            f"Expected total 38, got "
            f"{summary['total']}"
        )

    if summary["passed"] != 38:
        raise RuntimeError(
            f"Expected 38 PASS, got "
            f"{summary['passed']}"
        )

    if summary["failed"] != 0:
        raise RuntimeError(
            f"Expected 0 FAIL, got "
            f"{summary['failed']}"
        )

    if failure_ids:
        raise RuntimeError(
            "Failed vectors: "
            + ", ".join(failure_ids)
        )

    print()
    print(
        "CORE_CANONICAL_CONFORMANCE=38/38 PASS"
    )
    print(
        "CORE_PER_VECTOR_MEASUREMENT=38/38 COMPLETE"
    )
    print(
        "ERRORS=NONE"
    )


if __name__ == "__main__":
    main()