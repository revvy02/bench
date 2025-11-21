# Bench

A high-performance, composable benchmarking library for Luau with minimal overhead and hierarchical performance tracking.

## Overview

Bench provides a singleton API similar to `debug.profilebegin()` and `debug.profileend()` but with advanced analysis and topological awareness. It's designed for composable benchmarking with minimal measurement overhead through Structure of Arrays (SoA) design.

**Key Features:**
- **Composability**: Nest benchmarks and use incremental dumps
- **Minimal Overhead**: SoA design keeps `mark()` and `done()` fast
- **Topological Awareness**: Scope-aware hierarchical data extraction
- **Rich Analysis**: Statistics, percentiles, comparisons, and formatted output

## Quick Start

```luau
local bench = require(path.to.bench)

bench.on()

bench.mark("myFunction")
-- code to benchmark
bench.done()

local dump = bench.off()
local analysis = bench.analyze(dump.myFunction)
print(bench.format(analysis))
```

## API

### Control

**`bench.on(config?: BenchConfig)`** - Enable benchmarking

```luau
bench.on({
    track_memory = true,       -- Enable memory tracking (default: false)
    expected_results = 10000,  -- Pre-allocate for N measurements (default: 8192)
    expected_depth = 64,       -- Pre-allocate for N nesting levels (default: 256)
})
```

**`bench.off()`** - Disable and return final dump

### Measurement

**`bench.mark(label: string)`** - Start a measurement

**`bench.done()`** - Complete the most recent mark

**`bench.abort()`** - Force-complete all unclosed marks (for error recovery)

### Analysis

**`bench.dump()`** - Return measurements since last dump at current level (incremental)

**`bench.analyze(dump: Dump)`** - Compute statistics (min, max, avg, p10, p50, p90, std)

**`bench.compare(primary: Analysis, comparisons: { [string]: Analysis })`** - Add comparison deltas/percentages

**`bench.format(analysis: Analysis, options?: { verbose: boolean? })`** - Format as tree with ANSI colors

## Composability

Nest marks and use incremental dumps to analyze different parts independently:

```luau
bench.on()

bench.mark("test suite")
  bench.mark("test 1")
    for i = 1, 100 do
      bench.mark("iteration")
      -- work
      bench.done()
    end
  bench.done()
  local test1 = bench.dump()  -- Get test 1 results

  bench.mark("test 2")
    for i = 1, 100 do
      bench.mark("iteration")
      -- work
      bench.done()
    end
  bench.done()
  local test2 = bench.dump()  -- Get only test 2 (incremental!)
bench.done()

local suite = bench.dump()    -- Get entire suite with hierarchy
```

## Performance Focus: Structure of Arrays

The library uses Structure of Arrays (SoA) to minimize `mark()`/`done()` overhead.

**Traditional (Array of Structures):**
```luau
results[n] = { label = "foo", duration = 0.001, memory = 42 }
```

**Bench (Structure of Arrays):**
```luau
durations[n] = 0.001
labels[n] = "foo"
memories[n] = 42
```

**Benefits:**
- `mark()` and `done()` only write to pre-allocated arrays
- Dump tree construction is deferred until `dump()` is called
- Cache-friendly contiguous storage

**Overhead comparison:**
```luau
-- debug.profile*
debug.profilebegin("label")  -- String allocation, hash lookup
-- work
debug.profileend()           -- String allocation, hash lookup, recording

-- Bench
bench.mark("label")          -- Array write + os.clock()
-- work
bench.done()                 -- Array write + os.clock() + subtraction
```

## Topological Awareness

The dump system is scope-aware - each nesting level tracks what's been dumped, enabling incremental dumps that only return new measurements.

```luau
bench.mark("frame")
  bench.mark("update")
    -- update logic
  bench.done()
  local update_dump = bench.dump()  -- Gets update

  bench.mark("render")
    -- render logic
  bench.done()
  local render_dump = bench.dump()  -- Gets only render (incremental)
bench.done()

local frame_dump = bench.dump()     -- Gets frame with both children

-- frame_dump structure:
-- {
--   frame = {
--     durations = {...},
--     children = {
--       update = {...},
--       render = {...}
--     }
--   }
-- }
```

**Recursive labels** - Same label at different nesting levels:
```luau
bench.mark("recursive")
  bench.mark("recursive")  -- Child of first
    bench.mark("recursive")  -- Child of second
    bench.done()
  bench.done()
bench.done()
```

## Examples

### Basic Timing

```luau
bench.on()

bench.mark("computation")
complexCalculation()
bench.done()

local dump = bench.off()
print(bench.format(bench.analyze(dump.computation)))

-- Output:
-- computation
--   count: 1
--   time.avg: 123.45 μs
--   time.p50: 123.45 μs
```

### Nested Benchmarks

```luau
bench.on()

bench.mark("frame")
  bench.mark("update")
  bench.done()

  bench.mark("render")
    bench.mark("geometry")
    bench.done()

    bench.mark("lighting")
    bench.done()
  bench.done()
bench.done()

local dump = bench.dump()
print(bench.format(bench.analyze(dump.frame)))

-- Output (hierarchical):
-- frame
--   count: 1
--   time.avg: 16.67 ms
--   ├── update
--   │   time.avg: 2.34 ms
--   └── render
--       time.avg: 14.33 ms
--       ├── geometry
--       │   time.avg: 8.21 ms
--       └── lighting
--           time.avg: 6.12 ms
```

### Iterative Measurements

```luau
bench.on()

for i = 1, 1000 do
  bench.mark("iteration")
  doWork()
  bench.done()
end

local dump = bench.dump()
print(bench.format(bench.analyze(dump.iteration), { verbose = true }))

-- Output:
-- iteration
--   count: 1000
--   time.min: 45.23 μs
--   time.max: 892.11 μs
--   time.avg: 123.45 μs
--   time.p10: 67.89 μs
--   time.p50: 101.23 μs
--   time.p90: 234.56 μs
--   time.std: 78.90 μs
```

### Performance Comparisons

```luau
-- Baseline
bench.on()
for i = 1, 100 do
  bench.mark("task")
  oldImplementation()
  bench.done()
end
local baseline_dump = bench.off()

-- Current
bench.on()
for i = 1, 100 do
  bench.mark("task")
  newImplementation()
  bench.done()
end
local current_dump = bench.off()

-- Compare
local baseline = bench.analyze(baseline_dump.task)
local current = bench.compare(bench.analyze(current_dump.task), { baseline = baseline })
print(bench.format(current))

-- Output:
-- task
--   count: 100
--   time.avg: 89.12 μs (Δ -34.33 μs, -27.8%) ← green
--   time.p50: 87.65 μs (Δ -32.11 μs, -26.8%) ← green
```

### Memory Tracking

```luau
bench.on({ track_memory = true })

bench.mark("allocations")
local bigTable = table.create(10000, 0)
bench.done()

local dump = bench.dump()
print(bench.format(bench.analyze(dump.allocations)))

-- Note: Memory tracking uses gcinfo() and can be negative if GC occurs
-- Adds overhead to mark()/done() - use only when needed
```

## Types

```luau
export type BenchConfig = {
    track_memory: boolean?,
    expected_results: number?,
    expected_depth: number?,
}

export type Dump = {
    durations: { number },
    memories: { number }?,
    children: { [string]: Dump },
}

export type Analysis = {
    stats: Stats,
    comparisons: { [string]: ComparisonData? }?,
    children: { [string]: Analysis }?,
}

export type Stats = { [string]: number }
-- Keys: count, time.min/max/avg/p10/p50/p90/std, mem.* (if tracked)

export type ComparisonData = {
    delta: { [string]: number },
    pct: { [string]: number },
}

export type FormatOptions = {
    verbose: boolean?
}
```

## Statistics

For each metric (time, memory):
- **count** - Number of measurements
- **min/max** - Minimum/maximum value
- **avg** - Average (mean)
- **p10/p50/p90** - Percentiles (p50 = median)
- **std** - Standard deviation

## Statistical Analysis (`analysis.luau`)

Determines if benchmark results are **reliable** and **significant**.

### Why Use Statistical Analysis?

Benchmarks are noisy. Performance differences might be:
- **Real improvements** - Worth celebrating
- **Random noise** - Ignore and move on

The analysis module tells you which is which using statistical tests.

### What It Does

**For single benchmarks** - Reliability checks:
- Calculates confidence intervals and coefficient of variation
- Reports **stability**: CV < 5% = consistent results
- Reports **precision**: CI < ±5% of mean = narrow range

**For comparisons** - Significance testing:
- Runs Welch's t-test to detect real differences
- Adds significance stars: `*` (p<0.05), `**` (p<0.01), `***` (p<0.001)
- Calculates effect size: trivial, small, medium, large

**For convergence** - Auto-stop detection:
- Returns `true` if benchmark needs more iterations
- Used for adaptive benchmarking loops

### API

```luau
local analysis = require(path.to.bench.analysis)

-- Analyze single sample
local stats = analysis.analyze(durations, {
    confidence_level = 0.95,    -- 95% CI (default)
    cv_threshold = 5.0,         -- 5% CV (default)
    precision_threshold = 0.05, -- ±5% CI (default)
})

print("Mean:", stats.mean)
print("CV:", stats.cv, "%")
print("95% CI:", stats.ci_lower, "-", stats.ci_upper)
print("Stable:", stats.is_stable)
print("Precise:", stats.is_precise)
```

```luau
-- Compare two samples
local comp = analysis.compare(baseline_times, optimized_times)

print("Difference:", comp.mean_diff)
print("Significant:", comp.is_significant, comp.stars)
print("Effect size:", comp.effect_size)
print("Cohen's d:", comp.cohens_d)
```

```luau
-- Check convergence
if analysis.needs_more_samples(durations) then
    print("Need more iterations")
else
    print("Converged - results are stable")
end
```

### Key Concepts

**Coefficient of Variation (CV)** - Relative noise as percentage:
- CV < 5%: Excellent stability
- CV < 10%: Good stability
- CV > 20%: Poor reliability

```
CV = (std / mean) × 100%
```

**Confidence Interval (CI)** - Range where true mean likely falls:
- 95% CI: "We're 95% confident the real value is in this range"
- Narrower = more precise

**Statistical Significance** - Whether differences are real:
- `***` p < 0.001: Highly significant
- `**` p < 0.01: Very significant
- `*` p < 0.05: Significant
- (no stars): Not significant, likely noise

**Effect Size (Cohen's d)** - Magnitude of difference:
- < 0.2: Trivial (not worth it)
- < 0.5: Small
- < 0.8: Medium
- ≥ 0.8: Large (meaningful!)

**Important:** A difference can be statistically significant but trivially small. Always check effect size.

### Example: Detecting Real Improvements

```luau
local analysis = require(path.to.bench.analysis)

-- Collect baseline timings
local baseline_times = { 1.23, 1.25, 1.22, 1.24, 1.23 } -- ms

-- Collect optimized timings
local optimized_times = { 0.98, 1.01, 0.99, 1.00, 0.98 } -- ms

-- Compare
local comp = analysis.compare(baseline_times, optimized_times)

print(string.format(
    "%.2fms → %.2fms (%.1f%% faster) %s",
    comp.mean_diff,
    comp.is_significant and comp.stars or "",
    comp.effect_size
))

-- Output: "0.24ms faster (19.5%) *** large"
-- This is a real, meaningful improvement!
```

### Implementation Details

- **T-distribution**: Accurate CIs for small samples (n < 30)
- **Welch's t-test**: Robust comparison without equal variance assumption
- **Edge cases**: Handles empty samples, single values, zero variance
- **Performance**: Optimized for minimal allocations
