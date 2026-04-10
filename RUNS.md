# RUNS

Performance run ledger for Puma-like single-request concurrency benchmarks.

- Goal metric: response-time p95 (median of 3 runs).
- Goal: all models must satisfy `pure_response_p95 / gte_response_p95 >= 2.0`.
- Regression: compare against previous run; fail if GTE response-time p95 increases by more than 5%.
- Primary workload: in-process thread pool with concurrency `16`.

## 2026-04-10T18:25:40Z | v0.0.3 | 3123ee9
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-10T18:25:48Z",
  "generated_at": "2026-04-10T18:25:40Z",
  "gem_version": "0.0.3",
  "git_sha": "3123ee9",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 2.0,
    "regression_tolerance": 0.05
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": true,
    "regression_baseline": "none"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 34.43300002254546,
      "pure_response_p95_ms": 186.02799996733665,
      "response_ratio_p95": 5.402607958804995,
      "gte_response_median_ms": 22.49400003347546,
      "response_ratio_median": 4.421579083320585,
      "gte_service_p95_ms": 10.7089999364689,
      "pure_service_p95_ms": 2.7309999568387866,
      "service_ratio_p95": 0.2550191402596352,
      "gte_throughput_rps": 2280.5667250137117,
      "pure_throughput_rps": 413.3021288812272
    },
    "clip": {
      "gte_response_p95_ms": 48.33200003486127,
      "pure_response_p95_ms": 173.08700003195554,
      "response_ratio_p95": 3.5812091348818598,
      "gte_response_median_ms": 31.411000061780214,
      "response_ratio_median": 2.8353761341941808,
      "gte_service_p95_ms": 13.337999931536615,
      "pure_service_p95_ms": 2.561999950557947,
      "service_ratio_p95": 0.19208276830923554,
      "gte_throughput_rps": 1611.0193723928985,
      "pure_throughput_rps": 448.71722952293317
    },
    "siglip2": {
      "gte_response_p95_ms": 164.57000002264977,
      "pure_response_p95_ms": 353.6259999964386,
      "response_ratio_p95": 2.148787749576284,
      "gte_response_median_ms": 107.48000000603497,
      "response_ratio_median": 1.7185522881725033,
      "gte_service_p95_ms": 52.78799997176975,
      "pure_service_p95_ms": 4.851000034250319,
      "service_ratio_p95": 0.0918958861264788,
      "gte_throughput_rps": 476.814876903963,
      "pure_throughput_rps": 225.89106964629522
    }
  },
  "regressions": {}
}
```
