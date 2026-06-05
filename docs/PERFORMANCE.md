# Performance characterization

A quick benchmark of the realistic heavy case — copying a large ROM library — to confirm
the tool scales and doesn't blow up memory. Re-run with the snippet below if the copy path
changes.

## Method
- Source: **3,000 files × 128 KB = ~375 MB** of `.nes` files in one folder.
- Measured `New-PocketRomCopyPlan` (enumerate + match + free-space + problem checks) and
  `Invoke-PocketRomCopyPlan` (copy + per-file size verification) against a temp "card".
- Environment: Linux CI-class container with overlay/tmpfs storage (slower and faster than
  a real SD card in different ways — treat the absolute numbers as a sanity check, not a spec).

## Results (representative)
| Phase | Files | Size | Time | Throughput | Managed memory |
|---|---|---|---|---|---|
| Plan | 3,000 | 375 MB | ~2.3 s | — | ~12 MB |
| Copy + verify | 3,000 | 375 MB | ~13 s | ~230 files/s | ~28 MB |

## Conclusions
- **Memory is flat and small** (~tens of MB) even at 3,000 files — the in-memory plan
  (one lightweight object per file) is not a concern at realistic library sizes.
- **Copy is I/O-bound.** On a real SD card the card's write speed dominates; the per-file
  size verification (one `Get-Item` per file) adds negligible overhead relative to the write.
- No pathological slowdown or quadratic behaviour was observed.

## Progress feedback for long operations
- **CLI**: reports the count/size before copying and the copied/skipped/failed totals per
  system after.
- **Web UI**: shows a clear in-progress message during the operation (the local server is
  single-threaded — see [ARCHITECTURE.md](ARCHITECTURE.md) and #82). Per-file progress is
  not currently streamed; for typical libraries the copy completes in seconds-to-minutes.

## Re-run the benchmark
```powershell
Import-Module ./src/PocketPrep/PocketPrep.psd1 -Force
$src='/tmp/perf_src'; $root='/tmp/perf_root'
New-Item -ItemType Directory $src,$root -Force | Out-Null
$bytes=[byte[]]::new(131072); 1..3000 | ForEach-Object { [IO.File]::WriteAllBytes((Join-Path $src ("g{0:0000}.nes" -f $_)), $bytes) }
$nes = Get-PocketSystem ./manifests/systems.json -Id nes
$plan = Measure-Command { $global:p = New-PocketRomCopyPlan -System $nes -SourceFolder $src -Root $root }
$copy = Measure-Command { Invoke-PocketRomCopyPlan -Plan $global:p | Out-Null }
"plan $($plan.TotalSeconds)s, copy $($copy.TotalSeconds)s"
```
