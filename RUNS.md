# RUNS

Performance run ledger for Puma-like single-request concurrency benchmarks.

- Goal metric: response-time p95 (median of 3 runs).
- Goal: all models must satisfy `pure_response_p95 / gte_response_p95 >= 2.0`.
- Regression: compare against previous run; fail if GTE response-time p95 increases by more than 5%.
- Primary workload: in-process thread pool with concurrency `16`.

## Reproducibility Protocol

- Run benchmarks inside `nix develop .#default`.
- Keep benchmark settings fixed when comparing runs (`--iterations 80 --concurrency 16 --runs 3`).
- Avoid competing load while running (`no parallel builds/tests`, close heavy local workloads).
- Run two back-to-back replicates before claiming a win.

## Optimization Acceptance Gate

- Do not change Rust inference-path code unless a candidate configuration/change beats the current baseline by at least `5%` on `gte_response_p95_ms` for `e5`, `clip`, and `siglip2`.
- Require that improvement in two consecutive replicate runs under the reproducibility protocol.

## 2026-04-09T18:48:39Z | v0.0.1 | e1e944c
- Goal (p95 ratio all models): FAIL
- Regression vs previous run (GTE p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T18:48:50Z",
  "generated_at": "2026-04-09T18:48:39Z",
  "gem_version": "0.0.1",
  "git_sha": "e1e944c",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "thresholds": {
    "min_p95_ratio": 2.0,
    "regression_tolerance": 0.05
  },
  "status": {
    "goal_p95_ratio_all_models": false,
    "regression_vs_previous": true,
    "regression_baseline": "none"
  },
  "metrics": {
    "e5": {
      "gte_p95_ms": 24.80199991259724,
      "pure_p95_ms": 3.7609999999403954,
      "ratio_p95": 0.1516409972257978,
      "gte_median_ms": 12.34599994495511,
      "ratio_median": 0.2027377270471247,
      "gte_throughput_rps": 1123.8164805226238
    },
    "clip": {
      "gte_p95_ms": 35.88099998887628,
      "pure_p95_ms": 2.5779999559745193,
      "ratio_p95": 0.07184860948060931,
      "gte_median_ms": 11.706000077538192,
      "ratio_median": 0.1902443145471167,
      "gte_throughput_rps": 1069.9192199544443
    },
    "siglip2": {
      "gte_p95_ms": 52.96900006942451,
      "pure_p95_ms": 5.46399992890656,
      "ratio_p95": 0.1031546738987917,
      "gte_median_ms": 25.441000005230308,
      "ratio_median": 0.17648677640276939,
      "gte_throughput_rps": 533.8387006730702
    }
  },
  "regressions": {}
}
```

## 2026-04-09T18:49:35Z | v0.0.1 | e1e944c
- Goal (p95 ratio all models): FAIL
- Regression vs previous run (GTE p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T18:49:50Z",
  "generated_at": "2026-04-09T18:49:35Z",
  "gem_version": "0.0.1",
  "git_sha": "e1e944c",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 80,
  "thresholds": {
    "min_p95_ratio": 2.0,
    "regression_tolerance": 0.05
  },
  "status": {
    "goal_p95_ratio_all_models": false,
    "regression_vs_previous": false,
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_p95_ms": 45.13700003735721,
      "pure_p95_ms": 36.789000034332275,
      "ratio_p95": 0.8150519530293153,
      "gte_median_ms": 16.952999983914196,
      "ratio_median": 0.20073143129434892,
      "gte_throughput_rps": 768.4401621550355
    },
    "clip": {
      "gte_p95_ms": 32.64099999796599,
      "pure_p95_ms": 2.6150000048801303,
      "ratio_p95": 0.08011396725109779,
      "gte_median_ms": 11.636000010184944,
      "ratio_median": 0.19405293589566697,
      "gte_throughput_rps": 996.5991048348737
    },
    "siglip2": {
      "gte_p95_ms": 55.86999992374331,
      "pure_p95_ms": 7.012999965809286,
      "ratio_p95": 0.12552353634117228,
      "gte_median_ms": 32.41600003093481,
      "ratio_median": 0.1416584378195801,
      "gte_throughput_rps": 469.5138771324958
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_p95_ms": 24.80199991259724,
      "current_gte_p95_ms": 45.13700003735721,
      "allowed_gte_p95_ms": 26.0420999082271,
      "regressed": true
    },
    "clip": {
      "previous_gte_p95_ms": 35.88099998887628,
      "current_gte_p95_ms": 32.64099999796599,
      "allowed_gte_p95_ms": 37.6750499883201,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_p95_ms": 52.96900006942451,
      "current_gte_p95_ms": 55.86999992374331,
      "allowed_gte_p95_ms": 55.617450072895736,
      "regressed": true
    }
  }
}
```

## 2026-04-09T19:07:10Z | v0.0.1 | e1e944c
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T19:07:26Z",
  "generated_at": "2026-04-09T19:07:10Z",
  "gem_version": "0.0.1",
  "git_sha": "e1e944c",
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
      "gte_response_p95_ms": 70.18399995286018,
      "pure_response_p95_ms": 200.7019999437034,
      "response_ratio_p95": 2.859654623254688,
      "gte_response_median_ms": 47.09600005298853,
      "response_ratio_median": 2.2400628488492296,
      "gte_service_p95_ms": 27.63199992477894,
      "pure_service_p95_ms": 3.1370000215247273,
      "service_ratio_p95": 0.11352779495021745,
      "gte_throughput_rps": 1114.0354541532474,
      "pure_throughput_rps": 387.5386932642106
    },
    "clip": {
      "gte_response_p95_ms": 81.63399994373322,
      "pure_response_p95_ms": 179.134999983944,
      "response_ratio_p95": 2.1943675442513415,
      "gte_response_median_ms": 55.10199989657849,
      "response_ratio_median": 1.6855286587587757,
      "gte_service_p95_ms": 29.578999965451658,
      "pure_service_p95_ms": 2.5789999635890126,
      "service_ratio_p95": 0.08719023518716963,
      "gte_throughput_rps": 967.7380332010831,
      "pure_throughput_rps": 433.9877506643557
    },
    "siglip2": {
      "gte_response_p95_ms": 167.6679999800399,
      "pure_response_p95_ms": 377.0350000122562,
      "response_ratio_p95": 2.2486998118731094,
      "gte_response_median_ms": 103.1819999916479,
      "response_ratio_median": 1.9361516544570576,
      "gte_service_p95_ms": 62.784000067040324,
      "pure_service_p95_ms": 9.857999975793064,
      "service_ratio_p95": 0.15701452544066577,
      "gte_throughput_rps": 471.5868899449405,
      "pure_throughput_rps": 211.94017986914662
    }
  },
  "regressions": {}
}
```

## 2026-04-09T19:08:23Z | v0.0.1 | e1e944c
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T19:08:29Z",
  "generated_at": "2026-04-09T19:08:23Z",
  "gem_version": "0.0.1",
  "git_sha": "e1e944c",
  "platform": "arm64-darwin25",
  "ruby_version": "3.4.8",
  "mode": "puma_like_in_process",
  "concurrency": 16,
  "iterations": 40,
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
      "gte_response_p95_ms": 32.24900003988296,
      "pure_response_p95_ms": 95.68100003525615,
      "response_ratio_p95": 2.9669447088878917,
      "gte_response_median_ms": 22.923000040464103,
      "response_ratio_median": 2.2192121429707314,
      "gte_service_p95_ms": 22.8730000089854,
      "pure_service_p95_ms": 2.824000082910061,
      "service_ratio_p95": 0.12346435018583851,
      "gte_throughput_rps": 1219.7353174796235,
      "pure_throughput_rps": 405.72889222081915
    },
    "clip": {
      "gte_response_p95_ms": 38.14099996816367,
      "pure_response_p95_ms": 91.1189999897033,
      "response_ratio_p95": 2.389003960718398,
      "gte_response_median_ms": 30.430000042542815,
      "response_ratio_median": 1.6000328587314419,
      "gte_service_p95_ms": 23.542000097222626,
      "pure_service_p95_ms": 2.7540000155568123,
      "service_ratio_p95": 0.11698241458599416,
      "gte_throughput_rps": 1045.3690159884475,
      "pure_throughput_rps": 425.54096884021635
    },
    "siglip2": {
      "gte_response_p95_ms": 122.10000003688037,
      "pure_response_p95_ms": 200.83900005556643,
      "response_ratio_p95": 1.6448730548313095,
      "gte_response_median_ms": 96.44800005480647,
      "response_ratio_median": 1.1113449726896425,
      "gte_service_p95_ms": 71.9580000732094,
      "pure_service_p95_ms": 8.021000074222684,
      "service_ratio_p95": 0.11146780157956297,
      "gte_throughput_rps": 325.5075884998589,
      "pure_throughput_rps": 198.19837681111542
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 70.18399995286018,
      "current_gte_response_p95_ms": 32.24900003988296,
      "allowed_gte_response_p95_ms": 73.69319995050319,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 81.63399994373322,
      "current_gte_response_p95_ms": 38.14099996816367,
      "allowed_gte_response_p95_ms": 85.71569994091988,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 167.6679999800399,
      "current_gte_response_p95_ms": 122.10000003688037,
      "allowed_gte_response_p95_ms": 176.0513999790419,
      "regressed": false
    }
  }
}
```

## 2026-04-09T19:10:56Z | v0.0.1 | e1e944c
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T19:11:08Z",
  "generated_at": "2026-04-09T19:10:56Z",
  "gem_version": "0.0.1",
  "git_sha": "e1e944c",
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
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 64.93500003125519,
      "pure_response_p95_ms": 192.1149999834597,
      "response_ratio_p95": 2.9585739568951865,
      "gte_response_median_ms": 41.601000004448,
      "response_ratio_median": 2.4181389863612908,
      "gte_service_p95_ms": 23.78600009251386,
      "pure_service_p95_ms": 2.958000055514276,
      "service_ratio_p95": 0.12435886841038246,
      "gte_throughput_rps": 1213.721116721158,
      "pure_throughput_rps": 404.1057141282392
    },
    "clip": {
      "gte_response_p95_ms": 76.06200000736862,
      "pure_response_p95_ms": 183.48200002219528,
      "response_ratio_p95": 2.412268938555654,
      "gte_response_median_ms": 49.61200000252575,
      "response_ratio_median": 1.911714908891788,
      "gte_service_p95_ms": 27.59199996944517,
      "pure_service_p95_ms": 2.683000057004392,
      "service_ratio_p95": 0.0972383321243655,
      "gte_throughput_rps": 1044.2909905570575,
      "pure_throughput_rps": 425.3237775358533
    },
    "siglip2": {
      "gte_response_p95_ms": 154.78300000540912,
      "pure_response_p95_ms": 362.6219999277964,
      "response_ratio_p95": 2.3427766609713214,
      "gte_response_median_ms": 93.75999995972961,
      "response_ratio_median": 1.9983468440726908,
      "gte_service_p95_ms": 46.999999904073775,
      "pure_service_p95_ms": 5.246000015176833,
      "service_ratio_p95": 0.11161702182731557,
      "gte_throughput_rps": 505.1653156196031,
      "pure_throughput_rps": 220.2364237872313
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 70.18399995286018,
      "current_gte_response_p95_ms": 64.93500003125519,
      "allowed_gte_response_p95_ms": 73.69319995050319,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 81.63399994373322,
      "current_gte_response_p95_ms": 76.06200000736862,
      "allowed_gte_response_p95_ms": 85.71569994091988,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 167.6679999800399,
      "current_gte_response_p95_ms": 154.78300000540912,
      "allowed_gte_response_p95_ms": 176.0513999790419,
      "regressed": false
    }
  }
}
```

## 2026-04-09T19:58:23Z | v0.0.1 | ee62fbb
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-09T19:58:56Z",
  "generated_at": "2026-04-09T19:58:23Z",
  "gem_version": "0.0.1",
  "git_sha": "ee62fbb",
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
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 37.9020000109449,
      "pure_response_p95_ms": 194.98699996620417,
      "response_ratio_p95": 5.144504245419716,
      "gte_response_median_ms": 24.327000021003187,
      "response_ratio_median": 4.226209556125898,
      "gte_service_p95_ms": 15.424000099301338,
      "pure_service_p95_ms": 3.1129999551922083,
      "service_ratio_p95": 0.20182831529761322,
      "gte_throughput_rps": 2065.742246665769,
      "pure_throughput_rps": 395.6830975621541
    },
    "clip": {
      "gte_response_p95_ms": 51.08899995684624,
      "pure_response_p95_ms": 181.35500000789762,
      "response_ratio_p95": 3.549785671300754,
      "gte_response_median_ms": 32.242999994196,
      "response_ratio_median": 2.93710262818845,
      "gte_service_p95_ms": 16.592999920248985,
      "pure_service_p95_ms": 2.91300006210804,
      "service_ratio_p95": 0.17555596191820683,
      "gte_throughput_rps": 1496.5859121314356,
      "pure_throughput_rps": 426.61206017204063
    },
    "siglip2": {
      "gte_response_p95_ms": 119.64500008616596,
      "pure_response_p95_ms": 359.19600003398955,
      "response_ratio_p95": 3.00218145158848,
      "gte_response_median_ms": 74.89000004716218,
      "response_ratio_median": 2.4931900099108004,
      "gte_service_p95_ms": 32.58500003721565,
      "pure_service_p95_ms": 5.063000018708408,
      "service_ratio_p95": 0.15537824191885546,
      "gte_throughput_rps": 636.5828234695608,
      "pure_throughput_rps": 222.19753364356401
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 64.93500003125519,
      "current_gte_response_p95_ms": 37.9020000109449,
      "allowed_gte_response_p95_ms": 68.18175003281794,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 76.06200000736862,
      "current_gte_response_p95_ms": 51.08899995684624,
      "allowed_gte_response_p95_ms": 79.86510000773706,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 154.78300000540912,
      "current_gte_response_p95_ms": 119.64500008616596,
      "allowed_gte_response_p95_ms": 162.52215000567958,
      "regressed": false
    }
  }
}
```

## 2026-04-10T17:30:09Z | v0.0.2 | 49904e8
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-10T17:30:23Z",
  "generated_at": "2026-04-10T17:30:09Z",
  "gem_version": "0.0.2",
  "git_sha": "49904e8",
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
      "gte_response_p95_ms": 57.69700009841472,
      "pure_response_p95_ms": 291.04599996935576,
      "response_ratio_p95": 5.044387047383986,
      "gte_response_median_ms": 37.24600002169609,
      "response_ratio_median": 3.994093324242982,
      "gte_service_p95_ms": 15.080000041052699,
      "pure_service_p95_ms": 10.024999966844916,
      "service_ratio_p95": 0.6647877944001049,
      "gte_throughput_rps": 1358.5572132733284,
      "pure_throughput_rps": 268.5843589587752
    },
    "clip": {
      "gte_response_p95_ms": 52.20899998676032,
      "pure_response_p95_ms": 306.9570000516251,
      "response_ratio_p95": 5.879388613638765,
      "gte_response_median_ms": 35.16099997796118,
      "response_ratio_median": 4.976906237574731,
      "gte_service_p95_ms": 19.18199995998293,
      "pure_service_p95_ms": 7.1570000145584345,
      "service_ratio_p95": 0.37311020902352265,
      "gte_throughput_rps": 1485.1393235649336,
      "pure_throughput_rps": 255.67273897381497
    },
    "siglip2": {
      "gte_response_p95_ms": 215.66300000995398,
      "pure_response_p95_ms": 655.4870000109076,
      "response_ratio_p95": 3.0394040701495086,
      "gte_response_median_ms": 139.55399999395013,
      "response_ratio_median": 2.6833913753786316,
      "gte_service_p95_ms": 90.37999995052814,
      "pure_service_p95_ms": 162.3680000193417,
      "service_ratio_p95": 1.796503652447644,
      "gte_throughput_rps": 365.49540626350495,
      "pure_throughput_rps": 121.88563167035339
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 37.9020000109449,
      "current_gte_response_p95_ms": 57.69700009841472,
      "allowed_gte_response_p95_ms": 39.79710001149215,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 51.08899995684624,
      "current_gte_response_p95_ms": 52.20899998676032,
      "allowed_gte_response_p95_ms": 53.64344995468855,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 119.64500008616596,
      "current_gte_response_p95_ms": 215.66300000995398,
      "allowed_gte_response_p95_ms": 125.62725009047426,
      "regressed": true
    }
  }
}
```

## 2026-04-10T17:31:12Z | v0.0.2 | 49904e8
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-10T17:31:20Z",
  "generated_at": "2026-04-10T17:31:12Z",
  "gem_version": "0.0.2",
  "git_sha": "49904e8",
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
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 48.13000001013279,
      "pure_response_p95_ms": 196.8709999928251,
      "response_ratio_p95": 4.090400996288758,
      "gte_response_median_ms": 31.956000020727515,
      "response_ratio_median": 3.2408311404064007,
      "gte_service_p95_ms": 13.618999975733459,
      "pure_service_p95_ms": 3.240999998524785,
      "service_ratio_p95": 0.23797635687639682,
      "gte_throughput_rps": 1602.6604163989277,
      "pure_throughput_rps": 395.9513971121789
    },
    "clip": {
      "gte_response_p95_ms": 53.71100001502782,
      "pure_response_p95_ms": 184.9800000200048,
      "response_ratio_p95": 3.4439872645873133,
      "gte_response_median_ms": 32.75999997276813,
      "response_ratio_median": 2.9653846182958183,
      "gte_service_p95_ms": 23.640000028535724,
      "pure_service_p95_ms": 2.985999919474125,
      "service_ratio_p95": 0.12631133315861842,
      "gte_throughput_rps": 1437.4528329269235,
      "pure_throughput_rps": 420.7315469762352
    },
    "siglip2": {
      "gte_response_p95_ms": 181.42599996645004,
      "pure_response_p95_ms": 379.5890000183135,
      "response_ratio_p95": 2.0922524891057983,
      "gte_response_median_ms": 118.45299997366965,
      "response_ratio_median": 1.663165982633326,
      "gte_service_p95_ms": 57.044000015594065,
      "pure_service_p95_ms": 9.804000030271709,
      "service_ratio_p95": 0.17186733096542317,
      "gte_throughput_rps": 438.2024933313595,
      "pure_throughput_rps": 210.42331909895805
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 57.69700009841472,
      "current_gte_response_p95_ms": 48.13000001013279,
      "allowed_gte_response_p95_ms": 60.581850103335455,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 52.20899998676032,
      "current_gte_response_p95_ms": 53.71100001502782,
      "allowed_gte_response_p95_ms": 54.819449986098334,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 215.66300000995398,
      "current_gte_response_p95_ms": 181.42599996645004,
      "allowed_gte_response_p95_ms": 226.44615001045167,
      "regressed": false
    }
  }
}
```

## 2026-04-10T17:34:50Z | v0.0.2 | 49904e8
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +5.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-10T17:34:58Z",
  "generated_at": "2026-04-10T17:34:50Z",
  "gem_version": "0.0.2",
  "git_sha": "49904e8",
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
    "regression_baseline": "previous_run"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 34.29600002709776,
      "pure_response_p95_ms": 187.16699990909547,
      "response_ratio_p95": 5.457400272953468,
      "gte_response_median_ms": 22.324000019580126,
      "response_ratio_median": 4.3455025899332345,
      "gte_service_p95_ms": 9.741000016219914,
      "pure_service_p95_ms": 2.689999993890524,
      "service_ratio_p95": 0.27615234466803784,
      "gte_throughput_rps": 2252.3156603661337,
      "pure_throughput_rps": 415.45276560962225
    },
    "clip": {
      "gte_response_p95_ms": 44.643000001087785,
      "pure_response_p95_ms": 168.04800007957965,
      "response_ratio_p95": 3.7642631560487634,
      "gte_response_median_ms": 29.206000035628676,
      "response_ratio_median": 2.9809970542212154,
      "gte_service_p95_ms": 12.780999997630715,
      "pure_service_p95_ms": 2.4709999561309814,
      "service_ratio_p95": 0.19333385154440533,
      "gte_throughput_rps": 1736.412573920078,
      "pure_throughput_rps": 461.3237686582592
    },
    "siglip2": {
      "gte_response_p95_ms": 146.6419999487698,
      "pure_response_p95_ms": 350.17099999822676,
      "response_ratio_p95": 2.387931152879536,
      "gte_response_median_ms": 93.8000000314787,
      "response_ratio_median": 1.9393390189972493,
      "gte_service_p95_ms": 39.97100004926324,
      "pure_service_p95_ms": 4.7529999865219,
      "service_ratio_p95": 0.11891121014395307,
      "gte_throughput_rps": 536.2361583670439,
      "pure_throughput_rps": 227.94165832880446
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 48.13000001013279,
      "current_gte_response_p95_ms": 34.29600002709776,
      "allowed_gte_response_p95_ms": 50.53650001063943,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 53.71100001502782,
      "current_gte_response_p95_ms": 44.643000001087785,
      "allowed_gte_response_p95_ms": 56.39655001577921,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 181.42599996645004,
      "current_gte_response_p95_ms": 146.6419999487698,
      "allowed_gte_response_p95_ms": 190.49729996477254,
      "regressed": false
    }
  }
}
```
