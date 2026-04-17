# RUNS

Performance run ledger for Puma-like single-request concurrency benchmarks.

- Goal metric: response-time p95 (median of 3 runs).
- Goal: all models must satisfy `pure_response_p95 / gte_response_p95 >= 1.95`.
- Regression: compare against previous run; fail if GTE response-time p95 increases by more than 15%.
- Primary workload: in-process thread pool with concurrency `16`.

## 2026-04-16T18:38:43Z | v0.0.7 | b68e804
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-16T18:38:59Z",
  "generated_at": "2026-04-16T18:38:43Z",
  "gem_version": "0.0.7",
  "git_sha": "b68e804",
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
    "regression_baseline": "none"
  },
  "metrics": {
    "e5": {
      "gte_response_p95_ms": 66.01499998942018,
      "pure_response_p95_ms": 253.1139999628067,
      "response_ratio_p95": 3.834189199475449,
      "gte_response_median_ms": 44.68899988569319,
      "response_ratio_median": 3.0053928305823545,
      "gte_service_p95_ms": 18.61599995754659,
      "pure_service_p95_ms": 5.830999929457903,
      "service_ratio_p95": 0.3132251795635679,
      "gte_throughput_rps": 1203.0436974007505,
      "pure_throughput_rps": 311.8580112006981
    },
    "clip": {
      "gte_response_p95_ms": 85.68999986164272,
      "pure_response_p95_ms": 250.8399998769164,
      "response_ratio_p95": 2.9272960705091506,
      "gte_response_median_ms": 52.30799992568791,
      "response_ratio_median": 2.2256633789405216,
      "gte_service_p95_ms": 24.23500013537705,
      "pure_service_p95_ms": 7.236000150442123,
      "service_ratio_p95": 0.2985764435742408,
      "gte_throughput_rps": 922.4666753422866,
      "pure_throughput_rps": 314.39990893020695
    },
    "siglip2": {
      "gte_response_p95_ms": 632.3870001360774,
      "pure_response_p95_ms": 1306.933999992907,
      "response_ratio_p95": 2.066668036679565,
      "gte_response_median_ms": 375.20599993877113,
      "response_ratio_median": 2.1281322795276645,
      "gte_service_p95_ms": 187.54499987699091,
      "pure_service_p95_ms": 631.2430000398308,
      "service_ratio_p95": 3.365821538584646,
      "gte_throughput_rps": 125.30346934580264,
      "pure_throughput_rps": 61.189633552026606
    }
  },
  "regressions": {}
}
```

## 2026-04-16T18:59:06Z | v0.0.7 | d081d50
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-16T18:59:42Z",
  "generated_at": "2026-04-16T18:59:06Z",
  "gem_version": "0.0.7",
  "git_sha": "d081d50",
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
      "gte_response_p95_ms": 172.5039999000728,
      "pure_response_p95_ms": 895.7519999239594,
      "response_ratio_p95": 5.192644810803493,
      "gte_response_median_ms": 111.31599987857044,
      "response_ratio_median": 4.805050491480335,
      "gte_service_p95_ms": 60.870000161230564,
      "pure_service_p95_ms": 170.84000003524125,
      "service_ratio_p95": 2.8066370885941443,
      "gte_throughput_rps": 448.4430616103425,
      "pure_throughput_rps": 88.9285114700478
    },
    "clip": {
      "gte_response_p95_ms": 128.12300003133714,
      "pure_response_p95_ms": 462.9580001346767,
      "response_ratio_p95": 3.6133871359665592,
      "gte_response_median_ms": 80.69600001908839,
      "response_ratio_median": 3.1471572301995066,
      "gte_service_p95_ms": 38.715000031515956,
      "pure_service_p95_ms": 32.32300002127886,
      "service_ratio_p95": 0.8348960349984841,
      "gte_throughput_rps": 623.1209013314434,
      "pure_throughput_rps": 171.02860884819802
    },
    "siglip2": {
      "gte_response_p95_ms": 1507.93999992311,
      "pure_response_p95_ms": 3063.5430000256747,
      "response_ratio_p95": 2.031608021659937,
      "gte_response_median_ms": 903.0500000808388,
      "response_ratio_median": 2.093906206571585,
      "gte_service_p95_ms": 426.69199989177287,
      "pure_service_p95_ms": 1466.1380001343787,
      "service_ratio_p95": 3.4360569228067392,
      "gte_throughput_rps": 52.37240446371616,
      "pure_throughput_rps": 26.09981351512381
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 66.01499998942018,
      "current_gte_response_p95_ms": 172.5039999000728,
      "allowed_gte_response_p95_ms": 75.9172499878332,
      "regressed": true
    },
    "clip": {
      "previous_gte_response_p95_ms": 85.68999986164272,
      "current_gte_response_p95_ms": 128.12300003133714,
      "allowed_gte_response_p95_ms": 98.54349984088911,
      "regressed": true
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 632.3870001360774,
      "current_gte_response_p95_ms": 1507.93999992311,
      "allowed_gte_response_p95_ms": 727.245050156489,
      "regressed": true
    }
  }
}
```

## 2026-04-16T18:59:53Z | v0.0.7 | d081d50
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-16T19:00:07Z",
  "generated_at": "2026-04-16T18:59:53Z",
  "gem_version": "0.0.7",
  "git_sha": "d081d50",
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
      "gte_response_p95_ms": 60.40700012817979,
      "pure_response_p95_ms": 198.91799986362457,
      "response_ratio_p95": 3.292962726861677,
      "gte_response_median_ms": 38.240000139921904,
      "response_ratio_median": 2.836480110911166,
      "gte_service_p95_ms": 17.742000054568052,
      "pure_service_p95_ms": 3.025999991223216,
      "service_ratio_p95": 0.17055574241440205,
      "gte_throughput_rps": 1311.88402783581,
      "pure_throughput_rps": 391.041245231208
    },
    "clip": {
      "gte_response_p95_ms": 132.10599985904992,
      "pure_response_p95_ms": 199.3479998782277,
      "response_ratio_p95": 1.5090003488934751,
      "gte_response_median_ms": 88.25799985788763,
      "response_ratio_median": 1.2681456668474174,
      "gte_service_p95_ms": 37.98199980519712,
      "pure_service_p95_ms": 6.0090001206845045,
      "service_ratio_p95": 0.158206522866189,
      "gte_throughput_rps": 604.9652525807264,
      "pure_throughput_rps": 330.4556155811636
    },
    "siglip2": {
      "gte_response_p95_ms": 647.5259999278933,
      "pure_response_p95_ms": 1144.3499999586493,
      "response_ratio_p95": 1.7672649439344226,
      "gte_response_median_ms": 393.9869999885559,
      "response_ratio_median": 1.627396335413135,
      "gte_service_p95_ms": 158.79699983634055,
      "pure_service_p95_ms": 606.9249999709427,
      "service_ratio_p95": 3.8220180519559697,
      "gte_throughput_rps": 122.28975336622237,
      "pure_throughput_rps": 69.89805368140198
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 172.5039999000728,
      "current_gte_response_p95_ms": 60.40700012817979,
      "allowed_gte_response_p95_ms": 198.3795998850837,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 128.12300003133714,
      "current_gte_response_p95_ms": 132.10599985904992,
      "allowed_gte_response_p95_ms": 147.3414500360377,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 1507.93999992311,
      "current_gte_response_p95_ms": 647.5259999278933,
      "allowed_gte_response_p95_ms": 1734.1309999115763,
      "regressed": false
    }
  }
}
```

## 2026-04-16T19:00:17Z | v0.0.7 | d081d50
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +15.0%): FAIL

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-16T19:00:33Z",
  "generated_at": "2026-04-16T19:00:17Z",
  "gem_version": "0.0.7",
  "git_sha": "d081d50",
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
      "gte_response_p95_ms": 66.52099988423288,
      "pure_response_p95_ms": 322.6779999677092,
      "response_ratio_p95": 4.850768938068711,
      "gte_response_median_ms": 41.02699994109571,
      "response_ratio_median": 4.952592197532821,
      "gte_service_p95_ms": 22.419000044465065,
      "pure_service_p95_ms": 17.90199987590313,
      "service_ratio_p95": 0.7985191061330534,
      "gte_throughput_rps": 1184.2903872361255,
      "pure_throughput_rps": 245.21674087368797
    },
    "clip": {
      "gte_response_p95_ms": 92.00599999167025,
      "pure_response_p95_ms": 191.48799986578524,
      "response_ratio_p95": 2.0812555690185595,
      "gte_response_median_ms": 52.706999937072396,
      "response_ratio_median": 1.966133533363807,
      "gte_service_p95_ms": 36.30400006659329,
      "pure_service_p95_ms": 3.389999968931079,
      "service_ratio_p95": 0.09337813912276118,
      "gte_throughput_rps": 863.1292747471655,
      "pure_throughput_rps": 406.2769789729405
    },
    "siglip2": {
      "gte_response_p95_ms": 772.2239999566227,
      "pure_response_p95_ms": 1219.050999963656,
      "response_ratio_p95": 1.5786235600449254,
      "gte_response_median_ms": 489.5859998650849,
      "response_ratio_median": 1.311620431115213,
      "gte_service_p95_ms": 213.7360000051558,
      "pure_service_p95_ms": 664.5329999737442,
      "service_ratio_p95": 3.109129954512642,
      "gte_throughput_rps": 103.08228930649753,
      "pure_throughput_rps": 65.60716562000489
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 60.40700012817979,
      "current_gte_response_p95_ms": 66.52099988423288,
      "allowed_gte_response_p95_ms": 69.46805014740676,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 132.10599985904992,
      "current_gte_response_p95_ms": 92.00599999167025,
      "allowed_gte_response_p95_ms": 151.9218998379074,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 647.5259999278933,
      "current_gte_response_p95_ms": 772.2239999566227,
      "allowed_gte_response_p95_ms": 744.6548999170772,
      "regressed": true
    }
  }
}
```

## 2026-04-17T20:34:20Z | v0.0.7 | c7b9a73
- Goal (response-time p95 ratio all models): FAIL
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-17T20:34:34Z",
  "generated_at": "2026-04-17T20:34:20Z",
  "gem_version": "0.0.7",
  "git_sha": "c7b9a73",
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
      "gte_response_p95_ms": 53.15600009635091,
      "pure_response_p95_ms": 201.65099995210767,
      "response_ratio_p95": 3.7935698620399156,
      "gte_response_median_ms": 28.909000102430582,
      "response_ratio_median": 3.6016811259953734,
      "gte_service_p95_ms": 23.918000049889088,
      "pure_service_p95_ms": 3.0380000825971365,
      "service_ratio_p95": 0.12701731232796884,
      "gte_throughput_rps": 1463.8073608369239,
      "pure_throughput_rps": 386.8546780156357
    },
    "clip": {
      "gte_response_p95_ms": 74.74300009198487,
      "pure_response_p95_ms": 262.0589998550713,
      "response_ratio_p95": 3.5061343474647795,
      "gte_response_median_ms": 40.23500019684434,
      "response_ratio_median": 2.491338370252629,
      "gte_service_p95_ms": 41.57699993811548,
      "pure_service_p95_ms": 3.0720001086592674,
      "service_ratio_p95": 0.07388700755782596,
      "gte_throughput_rps": 1033.5383171261349,
      "pure_throughput_rps": 301.7922687638084
    },
    "siglip2": {
      "gte_response_p95_ms": 610.2509999182075,
      "pure_response_p95_ms": 1122.2670001443475,
      "response_ratio_p95": 1.8390252540262384,
      "gte_response_median_ms": 341.79900004528463,
      "response_ratio_median": 1.9067990252939606,
      "gte_service_p95_ms": 268.88099987991154,
      "pure_service_p95_ms": 566.7029998730868,
      "service_ratio_p95": 2.107634976536793,
      "gte_throughput_rps": 127.46261759590415,
      "pure_throughput_rps": 71.15614504888943
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 66.52099988423288,
      "current_gte_response_p95_ms": 53.15600009635091,
      "allowed_gte_response_p95_ms": 76.49914986686781,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 92.00599999167025,
      "current_gte_response_p95_ms": 74.74300009198487,
      "allowed_gte_response_p95_ms": 105.80689999042077,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 772.2239999566227,
      "current_gte_response_p95_ms": 610.2509999182075,
      "allowed_gte_response_p95_ms": 888.057599950116,
      "regressed": false
    }
  }
}
```

## 2026-04-20T13:26:02Z | v0.0.7 | c7b9a73
- Goal (response-time p95 ratio all models): PASS
- Regression vs previous run (GTE response-time p95 <= +15.0%): PASS

```json
{
  "kind": "puma_compare_run",
  "recorded_at": "2026-04-20T13:26:14Z",
  "generated_at": "2026-04-20T13:26:02Z",
  "gem_version": "0.0.7",
  "git_sha": "c7b9a73",
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
      "gte_response_p95_ms": 43.32199995405972,
      "pure_response_p95_ms": 191.58400013111532,
      "response_ratio_p95": 4.422325846781733,
      "gte_response_median_ms": 30.814999947324395,
      "response_ratio_median": 3.3430472232454185,
      "gte_service_p95_ms": 10.868999874219298,
      "pure_service_p95_ms": 2.7909998316317797,
      "service_ratio_p95": 0.25678534031929523,
      "gte_throughput_rps": 1803.8331414339848,
      "pure_throughput_rps": 405.82768562505095
    },
    "clip": {
      "gte_response_p95_ms": 48.99400006979704,
      "pure_response_p95_ms": 176.12600000575185,
      "response_ratio_p95": 3.594848343773566,
      "gte_response_median_ms": 31.333000166341662,
      "response_ratio_median": 2.954169710866817,
      "gte_service_p95_ms": 11.895000003278255,
      "pure_service_p95_ms": 2.6160001289099455,
      "service_ratio_p95": 0.21992434873383584,
      "gte_throughput_rps": 1615.1501090622432,
      "pure_throughput_rps": 441.36226472676816
    },
    "siglip2": {
      "gte_response_p95_ms": 422.6100000087172,
      "pure_response_p95_ms": 1029.102000175044,
      "response_ratio_p95": 2.4351103858257415,
      "gte_response_median_ms": 241.37699999846518,
      "response_ratio_median": 2.4074953296247914,
      "gte_service_p95_ms": 222.87100018002093,
      "pure_service_p95_ms": 536.363999824971,
      "service_ratio_p95": 2.406611893838725,
      "gte_throughput_rps": 183.95456325808652,
      "pure_throughput_rps": 77.7145699318021
    }
  },
  "regressions": {
    "e5": {
      "previous_gte_response_p95_ms": 53.15600009635091,
      "current_gte_response_p95_ms": 43.32199995405972,
      "allowed_gte_response_p95_ms": 61.12940011080354,
      "regressed": false
    },
    "clip": {
      "previous_gte_response_p95_ms": 74.74300009198487,
      "current_gte_response_p95_ms": 48.99400006979704,
      "allowed_gte_response_p95_ms": 85.9544501057826,
      "regressed": false
    },
    "siglip2": {
      "previous_gte_response_p95_ms": 610.2509999182075,
      "current_gte_response_p95_ms": 422.6100000087172,
      "allowed_gte_response_p95_ms": 701.7886499059387,
      "regressed": false
    }
  }
}
```
