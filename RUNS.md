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

## 2026-04-13T19:25:55Z | v0.0.3 | 1946c53
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T19:26:03Z",
  "generated_at": "2026-04-13T19:25:55Z",
  "gem_version": "0.0.3",
  "git_sha": "1946c53",
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
    "regression_vs_previous": false,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 39.06600014306605,
      "pure_response_p95_ms": 193.4549999423325,
      "response_ratio_p95": 4.952004280803481,
      "gte_response_median_ms": 26.292999973520637,
      "response_ratio_median": 3.7708515657048336,
      "gte_service_p95_ms": 10.224999859929085,
      "pure_service_p95_ms": 2.873999997973442,
      "service_ratio_p95": 0.2810757982732505,
      "gte_throughput_rps": 1994.5648140774251,
      "pure_throughput_rps": 400.8417676821181
    },
    "clip": {
      "gte_response_p95_ms": 53.5930001642555,
      "pure_response_p95_ms": 176.20800016447902,
      "response_ratio_p95": 3.287892068449698,
      "gte_response_median_ms": 33.964000176638365,
      "response_ratio_median": 2.6920857256046595,
      "gte_service_p95_ms": 15.446999808773398,
      "pure_service_p95_ms": 2.5740000419318676,
      "service_ratio_p95": 0.1666343026993448,
      "gte_throughput_rps": 1469.3997531141579,
      "pure_throughput_rps": 440.95842298679247
    },
    "siglip2": {
      "gte_response_p95_ms": 173.6660001333803,
      "pure_response_p95_ms": 364.5030001644045,
      "response_ratio_p95": 2.0988736994256567,
      "gte_response_median_ms": 115.13599986210465,
      "response_ratio_median": 1.6260856742918095,
      "gte_service_p95_ms": 58.80599981173873,
      "pure_service_p95_ms": 11.233999859541655,
      "service_ratio_p95": 0.19103492663174051,
      "gte_throughput_rps": 454.7159731884716,
      "pure_throughput_rps": 219.11564932892747
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 34.43300002254546,
      "current_gte_response_p95_ms": 39.06600014306605,
      "allowed_gte_response_p95_ms": 36.15465002367273,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 48.33200003486127,
      "current_gte_response_p95_ms": 53.5930001642555,
      "allowed_gte_response_p95_ms": 50.74860003660433,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 164.57000002264977,
      "current_gte_response_p95_ms": 173.6660001333803,
      "allowed_gte_response_p95_ms": 172.79850002378225,
      "regressed": true
    }
  }
}
```

## 2026-04-13T19:53:06Z | v0.0.3 | 1946c53
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T19:53:19Z",
  "generated_at": "2026-04-13T19:53:06Z",
  "gem_version": "0.0.3",
  "git_sha": "1946c53",
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
    "goal_response_p95_ratio_all_models": false,
    "regression_vs_previous": false,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 120.8049999549985,
      "pure_response_p95_ms": 429.87099988386035,
      "response_ratio_p95": 3.558387484325923,
      "gte_response_median_ms": 70.95499988645315,
      "response_ratio_median": 3.6170389721254383,
      "gte_service_p95_ms": 30.93699994497001,
      "pure_service_p95_ms": 20.072999875992537,
      "service_ratio_p95": 0.6488347257878238,
      "gte_throughput_rps": 631.9664426206564,
      "pure_throughput_rps": 185.32589554729802
    },
    "clip": {
      "gte_response_p95_ms": 86.44599979743361,
      "pure_response_p95_ms": 254.02599992230535,
      "response_ratio_p95": 2.938551240283611,
      "gte_response_median_ms": 54.4809999410063,
      "response_ratio_median": 2.492281713942094,
      "gte_service_p95_ms": 28.076000045984983,
      "pure_service_p95_ms": 8.056999882683158,
      "service_ratio_p95": 0.28697107385264276,
      "gte_throughput_rps": 902.069120207467,
      "pure_throughput_rps": 311.47675028411027
    },
    "siglip2": {
      "gte_response_p95_ms": 308.40699980035424,
      "pure_response_p95_ms": 533.8040001224726,
      "response_ratio_p95": 1.730842686670627,
      "gte_response_median_ms": 190.99100003950298,
      "response_ratio_median": 1.3567236153655517,
      "gte_service_p95_ms": 114.2019999679178,
      "pure_service_p95_ms": 77.67800008878112,
      "service_ratio_p95": 0.6801807333549571,
      "gte_throughput_rps": 224.63265554221715,
      "pure_throughput_rps": 149.6482331785097
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 39.06600014306605,
      "current_gte_response_p95_ms": 120.8049999549985,
      "allowed_gte_response_p95_ms": 41.01930015021935,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 53.5930001642555,
      "current_gte_response_p95_ms": 86.44599979743361,
      "allowed_gte_response_p95_ms": 56.272650172468275,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 173.6660001333803,
      "current_gte_response_p95_ms": 308.40699980035424,
      "allowed_gte_response_p95_ms": 182.3493001400493,
      "regressed": true
    }
  }
}
```

## 2026-04-13T20:01:14Z | v0.0.3 | 1946c53
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:01:23Z",
  "generated_at": "2026-04-13T20:01:14Z",
  "gem_version": "0.0.3",
  "git_sha": "1946c53",
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
    "goal_response_p95_ratio_all_models": false,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 40.935999946668744,
      "pure_response_p95_ms": 199.80500009842217,
      "response_ratio_p95": 4.880911675755504,
      "gte_response_median_ms": 26.898999931290746,
      "response_ratio_median": 3.948920043287336,
      "gte_service_p95_ms": 10.399999795481563,
      "pure_service_p95_ms": 3.172999946400523,
      "service_ratio_p95": 0.3050961546921454,
      "gte_throughput_rps": 1907.1230956147162,
      "pure_throughput_rps": 390.1278159290464
    },
    "clip": {
      "gte_response_p95_ms": 59.74099994637072,
      "pure_response_p95_ms": 178.91000001691282,
      "response_ratio_p95": 2.9947607200669504,
      "gte_response_median_ms": 38.349000038579106,
      "response_ratio_median": 2.392343992464566,
      "gte_service_p95_ms": 17.989999847486615,
      "pure_service_p95_ms": 2.7039998676627874,
      "service_ratio_p95": 0.15030571932109069,
      "gte_throughput_rps": 1288.4729957384632,
      "pure_throughput_rps": 435.0734455532371
    },
    "siglip2": {
      "gte_response_p95_ms": 210.21900000050664,
      "pure_response_p95_ms": 363.4350001811981,
      "response_ratio_p95": 1.7288399249369573,
      "gte_response_median_ms": 120.93400000594556,
      "response_ratio_median": 1.5706335703710135,
      "gte_service_p95_ms": 59.53199998475611,
      "pure_service_p95_ms": 5.963000003248453,
      "service_ratio_p95": 0.10016461742886769,
      "gte_throughput_rps": 376.6035070593988,
      "pure_throughput_rps": 219.804978045173
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 120.8049999549985,
      "current_gte_response_p95_ms": 40.935999946668744,
      "allowed_gte_response_p95_ms": 126.84524995274842,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 86.44599979743361,
      "current_gte_response_p95_ms": 59.74099994637072,
      "allowed_gte_response_p95_ms": 90.7682997873053,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 308.40699980035424,
      "current_gte_response_p95_ms": 210.21900000050664,
      "allowed_gte_response_p95_ms": 323.82734979037195,
      "regressed": false
    }
  }
}
```
