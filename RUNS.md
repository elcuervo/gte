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

## 2026-04-13T20:08:46Z | v0.0.3 | f898d54
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:08:54Z",
  "generated_at": "2026-04-13T20:08:46Z",
  "gem_version": "0.0.3",
  "git_sha": "f898d54",
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
      "gte_response_p95_ms": 41.53600009158254,
      "pure_response_p95_ms": 190.70399994961917,
      "response_ratio_p95": 4.59129428758515,
      "gte_response_median_ms": 27.17999997548759,
      "response_ratio_median": 3.6739882367071455,
      "gte_service_p95_ms": 10.617999825626612,
      "pure_service_p95_ms": 2.8029999230057,
      "service_ratio_p95": 0.26398568177036896,
      "gte_throughput_rps": 1876.6127225425805,
      "pure_throughput_rps": 407.950964623548
    },
    "clip": {
      "gte_response_p95_ms": 50.48600002191961,
      "pure_response_p95_ms": 172.0750001259148,
      "response_ratio_p95": 3.408370638418664,
      "gte_response_median_ms": 33.48300000652671,
      "response_ratio_median": 2.6841083541787794,
      "gte_service_p95_ms": 13.148999772965908,
      "pure_service_p95_ms": 2.4339999072253704,
      "service_ratio_p95": 0.18510912991493297,
      "gte_throughput_rps": 1538.165737805504,
      "pure_throughput_rps": 452.3709897036024
    },
    "siglip2": {
      "gte_response_p95_ms": 205.6559999473393,
      "pure_response_p95_ms": 380.7109999470413,
      "response_ratio_p95": 1.8512029799496583,
      "gte_response_median_ms": 130.16399997286499,
      "response_ratio_median": 1.4974801016187238,
      "gte_service_p95_ms": 66.03799993172288,
      "pure_service_p95_ms": 8.10900004580617,
      "service_ratio_p95": 0.1227929382202689,
      "gte_throughput_rps": 384.3419104466172,
      "pure_throughput_rps": 209.78324139664394
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 40.935999946668744,
      "current_gte_response_p95_ms": 41.53600009158254,
      "allowed_gte_response_p95_ms": 42.98279994400218,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 59.74099994637072,
      "current_gte_response_p95_ms": 50.48600002191961,
      "allowed_gte_response_p95_ms": 62.72804994368926,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 210.21900000050664,
      "current_gte_response_p95_ms": 205.6559999473393,
      "allowed_gte_response_p95_ms": 220.72995000053197,
      "regressed": false
    }
  }
}
```

## 2026-04-13T20:11:53Z | v0.0.3 | f898d54
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:12:01Z",
  "generated_at": "2026-04-13T20:11:53Z",
  "gem_version": "0.0.3",
  "git_sha": "f898d54",
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
      "gte_response_p95_ms": 38.36100012995303,
      "pure_response_p95_ms": 189.0869999770075,
      "response_ratio_p95": 4.929146772410781,
      "gte_response_median_ms": 23.754999972879887,
      "response_ratio_median": 4.189896869207535,
      "gte_service_p95_ms": 9.791000047698617,
      "pure_service_p95_ms": 2.6680000592023134,
      "service_ratio_p95": 0.27249515332495877,
      "gte_throughput_rps": 2060.421873871418,
      "pure_throughput_rps": 411.3173982955581
    },
    "clip": {
      "gte_response_p95_ms": 53.275000071153045,
      "pure_response_p95_ms": 229.29199994541705,
      "response_ratio_p95": 4.3039324193182384,
      "gte_response_median_ms": 34.43400003015995,
      "response_ratio_median": 2.720799207513026,
      "gte_service_p95_ms": 21.680999780073762,
      "pure_service_p95_ms": 4.305999958887696,
      "service_ratio_p95": 0.19860707543778439,
      "gte_throughput_rps": 1432.9470357014925,
      "pure_throughput_rps": 344.53651234740727
    },
    "siglip2": {
      "gte_response_p95_ms": 189.06100001186132,
      "pure_response_p95_ms": 373.25599999167025,
      "response_ratio_p95": 1.9742622749707919,
      "gte_response_median_ms": 121.08900002203882,
      "response_ratio_median": 1.5886166352763798,
      "gte_service_p95_ms": 65.61100017279387,
      "pure_service_p95_ms": 6.736000068485737,
      "service_ratio_p95": 0.10266571231570516,
      "gte_throughput_rps": 419.21690284100544,
      "pure_throughput_rps": 213.90488716120322
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 41.53600009158254,
      "current_gte_response_p95_ms": 38.36100012995303,
      "allowed_gte_response_p95_ms": 43.61280009616166,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 50.48600002191961,
      "current_gte_response_p95_ms": 53.275000071153045,
      "allowed_gte_response_p95_ms": 53.01030002301559,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 205.6559999473393,
      "current_gte_response_p95_ms": 189.06100001186132,
      "allowed_gte_response_p95_ms": 215.93879994470626,
      "regressed": false
    }
  }
}
```

## 2026-04-13T20:18:03Z | v0.0.3 | f898d54
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:18:11Z",
  "generated_at": "2026-04-13T20:18:03Z",
  "gem_version": "0.0.3",
  "git_sha": "f898d54",
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
      "gte_response_p95_ms": 40.748000144958496,
      "pure_response_p95_ms": 191.37200014665723,
      "response_ratio_p95": 4.696475887549405,
      "gte_response_median_ms": 27.205999940633774,
      "response_ratio_median": 3.8227229392357036,
      "gte_service_p95_ms": 10.979000013321638,
      "pure_service_p95_ms": 2.867999952286482,
      "service_ratio_p95": 0.2612259722020698,
      "gte_throughput_rps": 1908.7612172587392,
      "pure_throughput_rps": 406.248095614788
    },
    "clip": {
      "gte_response_p95_ms": 52.55099991336465,
      "pure_response_p95_ms": 178.60800004564226,
      "response_ratio_p95": 3.3987555011340342,
      "gte_response_median_ms": 35.37100018002093,
      "response_ratio_median": 2.650221924378864,
      "gte_service_p95_ms": 14.062999980524182,
      "pure_service_p95_ms": 2.6009997818619013,
      "service_ratio_p95": 0.18495340862291262,
      "gte_throughput_rps": 1487.320591420828,
      "pure_throughput_rps": 429.4518046467159
    },
    "siglip2": {
      "gte_response_p95_ms": 173.50800009444356,
      "pure_response_p95_ms": 356.62400000728667,
      "response_ratio_p95": 2.0553749672243917,
      "gte_response_median_ms": 110.25599995628,
      "response_ratio_median": 1.6837541713009059,
      "gte_service_p95_ms": 56.844000006094575,
      "pure_service_p95_ms": 5.007999949157238,
      "service_ratio_p95": 0.08810076610759801,
      "gte_throughput_rps": 455.1713151099738,
      "pure_throughput_rps": 223.68987632729264
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 38.36100012995303,
      "current_gte_response_p95_ms": 40.748000144958496,
      "allowed_gte_response_p95_ms": 40.27905013645068,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 53.275000071153045,
      "current_gte_response_p95_ms": 52.55099991336465,
      "allowed_gte_response_p95_ms": 55.9387500747107,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 189.06100001186132,
      "current_gte_response_p95_ms": 173.50800009444356,
      "allowed_gte_response_p95_ms": 198.5140500124544,
      "regressed": false
    }
  }
}
```

## 2026-04-13T20:20:40Z | v0.0.3 | f898d54
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:20:48Z",
  "generated_at": "2026-04-13T20:20:40Z",
  "gem_version": "0.0.3",
  "git_sha": "f898d54",
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
      "gte_response_p95_ms": 43.904999969527125,
      "pure_response_p95_ms": 196.7260001692921,
      "response_ratio_p95": 4.480719742758969,
      "gte_response_median_ms": 27.74999989196658,
      "response_ratio_median": 3.767279293455398,
      "gte_service_p95_ms": 10.743000078946352,
      "pure_service_p95_ms": 3.046999918296933,
      "service_ratio_p95": 0.28362653782981034,
      "gte_throughput_rps": 1791.432469872123,
      "pure_throughput_rps": 396.1003915555964
    },
    "clip": {
      "gte_response_p95_ms": 54.55399979837239,
      "pure_response_p95_ms": 183.44799987971783,
      "response_ratio_p95": 3.3626865226698004,
      "gte_response_median_ms": 37.92099980637431,
      "response_ratio_median": 2.5197911574014364,
      "gte_service_p95_ms": 16.47399994544685,
      "pure_service_p95_ms": 2.7489999774843454,
      "service_ratio_p95": 0.16686900489180378,
      "gte_throughput_rps": 1423.0064534372445,
      "pure_throughput_rps": 424.34465243645184
    },
    "siglip2": {
      "gte_response_p95_ms": 185.75699999928474,
      "pure_response_p95_ms": 366.15699995309114,
      "response_ratio_p95": 1.9711612480525689,
      "gte_response_median_ms": 114.52299985103309,
      "response_ratio_median": 1.6661020081871252,
      "gte_service_p95_ms": 64.00100002065301,
      "pure_service_p95_ms": 6.470999913290143,
      "service_ratio_p95": 0.1011077938032525,
      "gte_throughput_rps": 427.229470330236,
      "pure_throughput_rps": 217.76114315877965
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 40.748000144958496,
      "current_gte_response_p95_ms": 43.904999969527125,
      "allowed_gte_response_p95_ms": 42.78540015220642,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 52.55099991336465,
      "current_gte_response_p95_ms": 54.55399979837239,
      "allowed_gte_response_p95_ms": 55.17854990903288,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 173.50800009444356,
      "current_gte_response_p95_ms": 185.75699999928474,
      "allowed_gte_response_p95_ms": 182.18340009916574,
      "regressed": true
    }
  }
}
```

## 2026-04-13T20:23:10Z | v0.0.4 | 2d319db
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:23:18Z",
  "generated_at": "2026-04-13T20:23:10Z",
  "gem_version": "0.0.4",
  "git_sha": "2d319db",
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
      "gte_response_p95_ms": 39.80599995702505,
      "pure_response_p95_ms": 189.94099996052682,
      "response_ratio_p95": 4.7716675919607345,
      "gte_response_median_ms": 26.015999959781766,
      "response_ratio_median": 3.874654061999339,
      "gte_service_p95_ms": 11.414000065997243,
      "pure_service_p95_ms": 2.839999971911311,
      "service_ratio_p95": 0.24881723808393721,
      "gte_throughput_rps": 1987.8739786836381,
      "pure_throughput_rps": 408.912242689655
    },
    "clip": {
      "gte_response_p95_ms": 94.38999998383224,
      "pure_response_p95_ms": 186.49900006130338,
      "response_ratio_p95": 1.9758343054693102,
      "gte_response_median_ms": 37.4080000910908,
      "response_ratio_median": 2.6029726226628576,
      "gte_service_p95_ms": 48.67699998430908,
      "pure_service_p95_ms": 2.8170000296086073,
      "service_ratio_p95": 0.05787127453451653,
      "gte_throughput_rps": 837.8542559810112,
      "pure_throughput_rps": 417.51474378696116
    },
    "siglip2": {
      "gte_response_p95_ms": 173.02499990910292,
      "pure_response_p95_ms": 360.2809999138117,
      "response_ratio_p95": 2.0822482306203263,
      "gte_response_median_ms": 113.62299998290837,
      "response_ratio_median": 1.6439629299714098,
      "gte_service_p95_ms": 54.61900006048381,
      "pure_service_p95_ms": 5.121999885886908,
      "service_ratio_p95": 0.0937768886324342,
      "gte_throughput_rps": 457.89380248306185,
      "pure_throughput_rps": 221.3515727387357
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 43.904999969527125,
      "current_gte_response_p95_ms": 39.80599995702505,
      "allowed_gte_response_p95_ms": 46.10024996800348,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 54.55399979837239,
      "current_gte_response_p95_ms": 94.38999998383224,
      "allowed_gte_response_p95_ms": 57.28169978829101,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 185.75699999928474,
      "current_gte_response_p95_ms": 173.02499990910292,
      "allowed_gte_response_p95_ms": 195.04484999924898,
      "regressed": false
    }
  }
}
```

## 2026-04-13T20:24:47Z | v0.0.4 | 2d319db
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:24:55Z",
  "generated_at": "2026-04-13T20:24:47Z",
  "gem_version": "0.0.4",
  "git_sha": "2d319db",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 45.23599985986948,
      "pure_response_p95_ms": 190.33499993383884,
      "response_ratio_p95": 4.207600153051818,
      "gte_response_median_ms": 31.282000010833144,
      "response_ratio_median": 3.23019627522029,
      "gte_service_p95_ms": 12.748999986797571,
      "pure_service_p95_ms": 2.9860001523047686,
      "service_ratio_p95": 0.23421446038096858,
      "gte_throughput_rps": 1699.7407874572184,
      "pure_throughput_rps": 390.37720195777973
    },
    "clip": {
      "gte_response_p95_ms": 53.79000003449619,
      "pure_response_p95_ms": 177.05700010992587,
      "response_ratio_p95": 3.2916341326710734,
      "gte_response_median_ms": 34.98799982480705,
      "response_ratio_median": 2.6798045135592674,
      "gte_service_p95_ms": 14.666000148281455,
      "pure_service_p95_ms": 2.5839998852461576,
      "service_ratio_p95": 0.1761898172044508,
      "gte_throughput_rps": 1450.2474481602337,
      "pure_throughput_rps": 439.10203670506667
    },
    "siglip2": {
      "gte_response_p95_ms": 180.94700016081333,
      "pure_response_p95_ms": 363.73399989679456,
      "response_ratio_p95": 2.0101687210814916,
      "gte_response_median_ms": 109.65900006704032,
      "response_ratio_median": 1.7130103295983066,
      "gte_service_p95_ms": 57.98999988473952,
      "pure_service_p95_ms": 5.4090002086013556,
      "service_ratio_p95": 0.09327470631750721,
      "gte_throughput_rps": 435.9174155171058,
      "pure_throughput_rps": 219.44321762056518
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 39.80599995702505,
      "current_gte_response_p95_ms": 45.23599985986948,
      "allowed_gte_response_p95_ms": 45.77689995057881,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 94.38999998383224,
      "current_gte_response_p95_ms": 53.79000003449619,
      "allowed_gte_response_p95_ms": 108.54849998140706,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 173.02499990910292,
      "current_gte_response_p95_ms": 180.94700016081333,
      "allowed_gte_response_p95_ms": 198.97874989546833,
      "regressed": false
    }
  }
}
```

## 2026-04-13T20:26:07Z | v0.0.4 | e2df176
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-13T20:26:15Z",
  "generated_at": "2026-04-13T20:26:07Z",
  "gem_version": "0.0.4",
  "git_sha": "e2df176",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 40.3589999768883,
      "pure_response_p95_ms": 190.89099997654557,
      "response_ratio_p95": 4.729824824347974,
      "gte_response_median_ms": 26.53699996881187,
      "response_ratio_median": 3.8145608110132607,
      "gte_service_p95_ms": 10.873999912291765,
      "pure_service_p95_ms": 2.8849998489022255,
      "service_ratio_p95": 0.2653117410494988,
      "gte_throughput_rps": 1931.7139087878675,
      "pure_throughput_rps": 407.0770341977334
    },
    "clip": {
      "gte_response_p95_ms": 48.91000012867153,
      "pure_response_p95_ms": 177.71600000560284,
      "response_ratio_p95": 3.6335309658162105,
      "gte_response_median_ms": 30.460000038146973,
      "response_ratio_median": 3.0221273804678357,
      "gte_service_p95_ms": 20.64500004053116,
      "pure_service_p95_ms": 2.6499999221414328,
      "service_ratio_p95": 0.1283603737921452,
      "gte_throughput_rps": 1590.805148821742,
      "pure_throughput_rps": 437.4716329507029
    },
    "siglip2": {
      "gte_response_p95_ms": 170.85299990139902,
      "pure_response_p95_ms": 356.65099998004735,
      "response_ratio_p95": 2.087472857871236,
      "gte_response_median_ms": 109.8960000090301,
      "response_ratio_median": 1.6882325096942958,
      "gte_service_p95_ms": 62.66900012269616,
      "pure_service_p95_ms": 5.041000200435519,
      "service_ratio_p95": 0.080438497352216,
      "gte_throughput_rps": 461.6565395456102,
      "pure_throughput_rps": 223.86827577919232
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 45.23599985986948,
      "current_gte_response_p95_ms": 40.3589999768883,
      "allowed_gte_response_p95_ms": 52.021399838849895,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 53.79000003449619,
      "current_gte_response_p95_ms": 48.91000012867153,
      "allowed_gte_response_p95_ms": 61.85850003967061,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 180.94700016081333,
      "current_gte_response_p95_ms": 170.85299990139902,
      "allowed_gte_response_p95_ms": 208.0890501849353,
      "regressed": false
    }
  }
}
```

## 2026-04-14T00:34:10Z | v0.0.4 | dc15c02
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +15.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-14T00:34:19Z",
  "generated_at": "2026-04-14T00:34:10Z",
  "gem_version": "0.0.4",
  "git_sha": "dc15c02",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": false,
    "regression_vs_previous": false,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 68.15299997106194,
      "pure_response_p95_ms": 196.67800003662705,
      "response_ratio_p95": 2.8858304127498036,
      "gte_response_median_ms": 45.1859999448061,
      "response_ratio_median": 2.2784490799701174,
      "gte_service_p95_ms": 21.412000060081482,
      "pure_service_p95_ms": 3.063000040128827,
      "service_ratio_p95": 0.1430506272900305,
      "gte_throughput_rps": 1161.9293849082817,
      "pure_throughput_rps": 395.7946813740145
    },
    "clip": {
      "gte_response_p95_ms": 74.4900000281632,
      "pure_response_p95_ms": 180.30000012367964,
      "response_ratio_p95": 2.420459122775027,
      "gte_response_median_ms": 46.62100016139448,
      "response_ratio_median": 2.027627030550416,
      "gte_service_p95_ms": 23.69199995882809,
      "pure_service_p95_ms": 2.624999964609742,
      "service_ratio_p95": 0.11079689216492747,
      "gte_throughput_rps": 1062.8545629626458,
      "pure_throughput_rps": 431.31102378653344
    },
    "siglip2": {
      "gte_response_p95_ms": 205.81400021910667,
      "pure_response_p95_ms": 367.17400001361966,
      "response_ratio_p95": 1.7840088605378226,
      "gte_response_median_ms": 121.86000007204711,
      "response_ratio_median": 1.5885934670446002,
      "gte_service_p95_ms": 77.13999995030463,
      "pure_service_p95_ms": 6.241000024601817,
      "service_ratio_p95": 0.08090484869876087,
      "gte_throughput_rps": 385.22656152702854,
      "pure_throughput_rps": 216.30098285327693
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 40.3589999768883,
      "current_gte_response_p95_ms": 68.15299997106194,
      "allowed_gte_response_p95_ms": 46.41284997342154,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 48.91000012867153,
      "current_gte_response_p95_ms": 74.4900000281632,
      "allowed_gte_response_p95_ms": 56.24650014797225,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 170.85299990139902,
      "current_gte_response_p95_ms": 205.81400021910667,
      "allowed_gte_response_p95_ms": 196.48094988660884,
      "regressed": true
    }
  }
}
```

## 2026-04-14T13:52:51Z | v0.0.5 | dc15c02
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-14T13:52:58Z",
  "generated_at": "2026-04-14T13:52:51Z",
  "gem_version": "0.0.5",
  "git_sha": "dc15c02",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 52.52899997867644,
      "pure_response_p95_ms": 188.65499994717538,
      "response_ratio_p95": 3.591444726222806,
      "gte_response_median_ms": 32.26399980485439,
      "response_ratio_median": 3.06040790508823,
      "gte_service_p95_ms": 14.816999901086092,
      "pure_service_p95_ms": 2.7439999394118786,
      "service_ratio_p95": 0.18519268122629481,
      "gte_throughput_rps": 1479.672991157009,
      "pure_throughput_rps": 409.35792245164544
    },
    "clip": {
      "gte_response_p95_ms": 62.61799996718764,
      "pure_response_p95_ms": 178.5619999282062,
      "response_ratio_p95": 2.8516081641345012,
      "gte_response_median_ms": 41.66599991731346,
      "response_ratio_median": 2.280924494233597,
      "gte_service_p95_ms": 18.202000064775348,
      "pure_service_p95_ms": 2.5259999092668295,
      "service_ratio_p95": 0.1387759532072063,
      "gte_throughput_rps": 1252.7796028659877,
      "pure_throughput_rps": 434.81805579476423
    },
    "siglip2": {
      "gte_response_p95_ms": 170.83100019954145,
      "pure_response_p95_ms": 356.5559999551624,
      "response_ratio_p95": 2.0871855783709186,
      "gte_response_median_ms": 111.13699991255999,
      "response_ratio_median": 1.6631814801079454,
      "gte_service_p95_ms": 47.64100001193583,
      "pure_service_p95_ms": 5.046000005677342,
      "service_ratio_p95": 0.10591717227625644,
      "gte_throughput_rps": 466.4478248762771,
      "pure_throughput_rps": 223.68299637690873
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 68.15299997106194,
      "current_gte_response_p95_ms": 52.52899997867644,
      "allowed_gte_response_p95_ms": 78.37594996672124,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 74.4900000281632,
      "current_gte_response_p95_ms": 62.61799996718764,
      "allowed_gte_response_p95_ms": 85.66350003238767,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 205.81400021910667,
      "current_gte_response_p95_ms": 170.83100019954145,
      "allowed_gte_response_p95_ms": 236.68610025197265,
      "regressed": false
    }
  }
}
```

## 2026-04-14T14:57:02Z | v0.0.5 | c2d01d3
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-14T14:57:10Z",
  "generated_at": "2026-04-14T14:57:02Z",
  "gem_version": "0.0.5",
  "git_sha": "c2d01d3",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": false,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 60.735000064596534,
      "pure_response_p95_ms": 201.12099987454712,
      "response_ratio_p95": 3.3114513815862163,
      "gte_response_median_ms": 38.16900006495416,
      "response_ratio_median": 2.8897272617977485,
      "gte_service_p95_ms": 18.41200003400445,
      "pure_service_p95_ms": 3.6150000523775816,
      "service_ratio_p95": 0.19633934638828862,
      "gte_throughput_rps": 1315.486566293231,
      "pure_throughput_rps": 387.59314340252337
    },
    "clip": {
      "gte_response_p95_ms": 74.35299991630018,
      "pure_response_p95_ms": 189.49200003407896,
      "response_ratio_p95": 2.548545455427377,
      "gte_response_median_ms": 47.99499991349876,
      "response_ratio_median": 2.1228461340180367,
      "gte_service_p95_ms": 21.982999984174967,
      "pure_service_p95_ms": 3.349000122398138,
      "service_ratio_p95": 0.15234499953641462,
      "gte_throughput_rps": 1065.4875254369254,
      "pure_throughput_rps": 407.7201816635546
    },
    "siglip2": {
      "gte_response_p95_ms": 194.50900005176663,
      "pure_response_p95_ms": 388.6649999767542,
      "response_ratio_p95": 1.9981851732995124,
      "gte_response_median_ms": 121.37699988670647,
      "response_ratio_median": 1.6399812169430892,
      "gte_service_p95_ms": 66.6649998165667,
      "pure_service_p95_ms": 8.696999866515398,
      "service_ratio_p95": 0.13045825981318213,
      "gte_throughput_rps": 406.3038033579813,
      "pure_throughput_rps": 205.49546243216415
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 52.52899997867644,
      "current_gte_response_p95_ms": 60.735000064596534,
      "allowed_gte_response_p95_ms": 60.4083499754779,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 62.61799996718764,
      "current_gte_response_p95_ms": 74.35299991630018,
      "allowed_gte_response_p95_ms": 72.01069996226579,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 170.83100019954145,
      "current_gte_response_p95_ms": 194.50900005176663,
      "allowed_gte_response_p95_ms": 196.45565022947264,
      "regressed": false
    }
  }
}
```

## 2026-04-14T15:01:32Z | v0.0.5 | c2d01d3
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-14T15:01:41Z",
  "generated_at": "2026-04-14T15:01:32Z",
  "gem_version": "0.0.5",
  "git_sha": "c2d01d3",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": false,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 65.96800009720027,
      "pure_response_p95_ms": 385.2239998523146,
      "response_ratio_p95": 5.839558563010973,
      "gte_response_median_ms": 41.13100003451109,
      "response_ratio_median": 5.078043319145708,
      "gte_service_p95_ms": 25.436999974772334,
      "pure_service_p95_ms": 13.61000002361834,
      "service_ratio_p95": 0.5350473733976623,
      "gte_throughput_rps": 1205.2185972580528,
      "pure_throughput_rps": 203.9838036718972
    },
    "clip": {
      "gte_response_p95_ms": 80.36700007505715,
      "pure_response_p95_ms": 306.70999991707504,
      "response_ratio_p95": 3.816367409889997,
      "gte_response_median_ms": 51.74500006251037,
      "response_ratio_median": 2.6511933512009462,
      "gte_service_p95_ms": 25.96500003710389,
      "pure_service_p95_ms": 16.3569999858737,
      "service_ratio_p95": 0.6299634108415022,
      "gte_throughput_rps": 961.711848481514,
      "pure_throughput_rps": 258.1786144665668
    },
    "siglip2": {
      "gte_response_p95_ms": 213.37699983268976,
      "pure_response_p95_ms": 392.34500005841255,
      "response_ratio_p95": 1.8387408219538783,
      "gte_response_median_ms": 130.5839999113232,
      "response_ratio_median": 1.5574879023464376,
      "gte_service_p95_ms": 81.02500019595027,
      "pure_service_p95_ms": 9.13699995726347,
      "service_ratio_p95": 0.11276766350097643,
      "gte_throughput_rps": 368.6771860554016,
      "pure_throughput_rps": 203.41534362419392
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 60.735000064596534,
      "current_gte_response_p95_ms": 65.96800009720027,
      "allowed_gte_response_p95_ms": 69.84525007428601,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 74.35299991630018,
      "current_gte_response_p95_ms": 80.36700007505715,
      "allowed_gte_response_p95_ms": 85.5059499037452,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 194.50900005176663,
      "current_gte_response_p95_ms": 213.37699983268976,
      "allowed_gte_response_p95_ms": 223.6853500595316,
      "regressed": false
    }
  }
}
```

## 2026-04-14T15:11:26Z | v0.0.5 | c2d01d3
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-14T15:11:34Z",
  "generated_at": "2026-04-14T15:11:26Z",
  "gem_version": "0.0.5",
  "git_sha": "c2d01d3",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "run_samples": 3,
  "thresholds": {
    "goal_metric": "response_time_p95",
    "sample_aggregation": "median",
    "min_p95_ratio": 1.95,
    "regression_tolerance": 0.15
  },
  "status": {
    "goal_response_p95_ratio_all_models": true,
    "regression_vs_previous": true,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 45.66600010730326,
      "pure_response_p95_ms": 216.77000005729496,
      "response_ratio_p95": 4.74685760846016,
      "gte_response_median_ms": 30.374000081792474,
      "response_ratio_median": 3.7617040765453695,
      "gte_service_p95_ms": 11.493999976664782,
      "pure_service_p95_ms": 3.7849999498575926,
      "service_ratio_p95": 0.32930224095544913,
      "gte_throughput_rps": 1693.7669403802067,
      "pure_throughput_rps": 361.5900925850168
    },
    "clip": {
      "gte_response_p95_ms": 69.19700000435114,
      "pure_response_p95_ms": 222.24400006234646,
      "response_ratio_p95": 3.2117577358609717,
      "gte_response_median_ms": 46.05100001208484,
      "response_ratio_median": 2.5851555896046614,
      "gte_service_p95_ms": 19.563999958336353,
      "pure_service_p95_ms": 4.669000161811709,
      "service_ratio_p95": 0.23865263605371337,
      "gte_throughput_rps": 1136.4282052806357,
      "pure_throughput_rps": 352.35150611070355
    },
    "siglip2": {
      "gte_response_p95_ms": 137.83499994315207,
      "pure_response_p95_ms": 399.1339998319745,
      "response_ratio_p95": 2.8957376573191946,
      "gte_response_median_ms": 88.03600003011525,
      "response_ratio_median": 2.3919532903369958,
      "gte_service_p95_ms": 40.812999941408634,
      "pure_service_p95_ms": 7.936000125482678,
      "service_ratio_p95": 0.1944478508532978,
      "gte_throughput_rps": 552.329796227751,
      "pure_throughput_rps": 200.09904901474883
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 65.96800009720027,
      "current_gte_response_p95_ms": 45.66600010730326,
      "allowed_gte_response_p95_ms": 75.86320011178032,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 80.36700007505715,
      "current_gte_response_p95_ms": 69.19700000435114,
      "allowed_gte_response_p95_ms": 92.4220500863157,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 213.37699983268976,
      "current_gte_response_p95_ms": 137.83499994315207,
      "allowed_gte_response_p95_ms": 245.3835498075932,
      "regressed": false
    }
  }
}
```
