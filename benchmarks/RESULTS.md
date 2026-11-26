# ZoomCast — Reproducible Benchmarks

Measured on **Apple M2 (8 GB RAM, macOS 27.2)** with the release build (`swift build -c release`).

## How to Reproduce

```bash
./benchmarks/run_benchmarks.sh
```

The script builds `ZoomCastBench` in release mode and executes it under `/usr/bin/time -l`.

## Results (`v1.0.0`)

| Benchmark | Workload | Time | Throughput | Output Size |
|---|---|---:|---:|---:|
| **Spring Camera Engine** | 10,000 timestamp evaluations (easing + cursor lerp + click ripples) | **`6.54 ms`** | ~1.53M evals/s | — |
| **1080p Auto-Zoom MP4 Export** | 180 frames (`1920×1080`, 6 s @ 30 fps) gradient + drop shadow + rounded corners + zoom crop + cursor + H.264 encode | **`5.66 s`** (`5,664.1 ms`) | **`31.8 fps`** (>1× real-time) | `2.56 MB` (`2,684,538` B) |
| **Web Animated GIF Export** | 90 frames (`960×540`, 6 s @ 15 fps) full studio compositing + `ImageIO` GIF | **`2.96 s`** (`2,961.4 ms`) | **`30.4 fps`** (2× real-time) | `1.11 MB` (`1,168,242` B) |
| **Demo Recording Generation** | Synthetic 180-frame `1920×1080` H.264 source clip | **`1.41 s`** (`1,411.1 ms`) | `127.6 fps` | — |

- **Combined Peak RSS** (full sequential Demo + 1080p MP4 + 960p GIF run): **`430.5 MB`** (`451,362,816` bytes)
- **Signed App Bundle (`build/ZoomCast.app`):** **`2.7 MB`** (zero external Swift packages)
