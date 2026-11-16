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

    runner_path = Path(
        args.runner
    ).resolve()

    sys.path.insert(
        0,
        str(harness_dir),
    )

    import harness as base_harness
    import enforcement_v2_runner as hc2

    class TimedTarget(hc2.RunnerTarget):
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

    class TimedHarness(hc2.RunnerHarness):
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

    verifier = base_harness.ResponseVerifier(
        public_key=(
            key_loader.public_key
            if key_loader
            else None
        )
    )

    harness = TimedHarness(
        target,
        verifier,
        schemas,
        None,
    )

    files = sorted(
        vectors_dir.glob("*.json")
    )

    if len(files) != 55:
        raise RuntimeError(
            f"Expected 55 HC2 vectors, "
            f"got {len(files)}"
        )

    print()
    print("=== CANONICAL HC2-55 EXECUTION ===")
    print("VECTOR_SET=enforcement-v2")
    print("EXPECTED_VECTOR_COUNT=55")

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

    runner_times = []
    vector_times = []
    failure_ids = []

    print()
    print("=== HC2-55 FULL VECTOR REPORT ===")

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

            runner_times.append(
                runner_ms
            )

            vector_times.append(
                vector_ms
            )

            runner_text = (
                f"{runner_ms:.3f}"
            )

            vector_text = (
                f"{vector_ms:.3f}"
            )

            execution_path = "ADA_RUNNER"

        else:
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
            vector_text = (
                f"{preflight_ms:.3f}"
            )

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
        print(f"[{index:02d}/55] {test_id}")
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
            failure_ids.append(
                test_id
            )

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
    print("=== HC2-55 AGGREGATES ===")

    print(
        f"HC2_TOTAL="
        f"{summary['total']}"
    )

    print(
        f"HC2_PASSED="
        f"{summary['passed']}"
    )

    print(
        f"HC2_FAILED="
        f"{summary['failed']}"
    )

    print(
        f"HC2_SUITE_WALL_MS="
        f"{suite_ms:.3f}"
    )

    print()
    stats(
        "HC2_TARGET_EVALUATE",
        runner_times,
    )

    print()
    stats(
        "HC2_VECTOR_TOTAL",
        vector_times,
    )

    print()
    print(
        f"HC2_ADA_RUNNER_VECTOR_COUNT="
        f"{len(runner_times)}"
    )

    print(
        f"HC2_PREFLIGHT_ONLY_VECTOR_COUNT="
        f"{55 - len(runner_times)}"
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
        "RunnerTarget.evaluate + canonical response verification"
    )

    if summary["total"] != 55:
        raise RuntimeError(
            f"Expected total 55, got "
            f"{summary['total']}"
        )

    if summary["passed"] != 55:
        raise RuntimeError(
            f"Expected 55 PASS, got "
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
        "HC2_CANONICAL_CONFORMANCE=55/55 PASS"
    )

    print(
        "HC2_PER_VECTOR_MEASUREMENT=55/55 COMPLETE"
    )

    print(
        "ERRORS=NONE"
    )


if __name__ == "__main__":
    main()