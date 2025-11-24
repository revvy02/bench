# Bench

A high-performance, composable benchmarking library for Luau with minimal overhead and hierarchical performance tracking.

## Overview

`bench` provides a an api similar to `debug.profilebegin()` and `debug.profileend()`. It marks 
scopes and allows tracking hierarchical performance traces. It's designed for 
composable benchmarking with minimal measurement overhead through Structure of Arrays (SoA) design.

**Key Features:**
- **Composability**: Nest benchmarks and use incremental dumps
- **Minimal Overhead**: `mark()` and `done()` are extremely fast for usage in hot
- **Topological Awareness**: Scope-aware hierarchical data extraction
- **Rich Analysis**: Statistics, percentiles, comparisons, and nicely formatted output

## CLI Output
<p align="center">
  <img src="docs/images/image.png" width="70%" />
</p>

## Quick Start

```luau
local bench = require(path.to.bench)

bench.on()

bench.mark("function1")
-- code to benchmark
bench.done()

bench.mark("function2")

bench.done()

local dump = bench.off()
local analysis = bench.analyze(dump.function1)
print(bench.cli(analysis)) -- outputs analysis formatted for cli
```

## Usage

### Running Benchmarks in Roblox Studio

Use [rodeo](https://github.com/revvy02/rodeo) to run benchmark scripts in your active Roblox Studio instance and pipe formatted output back to your terminal:

```bash
# Run a benchmark script in Studio and view CLI output
rodeo run path/to/benchmark.luau

# Example benchmark.luau:
local bench = require(path.to.bench)

bench.on()

for i = 1, 1000 do
    bench.mark("operation")
    -- your code to benchmark
    bench.done()
end

local dump = bench.off()
local analysis = bench.analyze(dump.operation)
print(bench.cli(analysis))  -- Formatted output appears in terminal
```

The `bench.cli()` function generates formatted terminal output with:
- ANSI colors (green for fast, yellow/red for slow)
- Auto-scaled units (s → ms → μs → ns)
- Tree structure for nested benchmarks
- Statistical summaries and comparisons

### Standalone Usage

For non-Studio environments (Lune, roblox-cli, etc.), simply run your benchmark script:

```bash
lune run benchmark.luau
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

**`bench.cli(analysis: Analysis, options?: { verbose: boolean? })`** - Format as tree with ANSI colors

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
print(bench.cli(bench.analyze(dump.computation)))

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
print(bench.cli(bench.analyze(dump.frame)))

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
print(bench.cli(bench.analyze(dump.iteration), { verbose = true }))

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
print(bench.cli(current))

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
print(bench.cli(bench.analyze(dump.allocations)))

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
- **cv** - Coefficient of Variation (relative variability as percentage)
- **mad** - Median Absolute Deviation (robust alternative to standard deviation)

## Statistical Analysis (`analysis.luau`)

Determines if benchmark results are **reliable** and **significant**.

### Why Use Statistical Analysis?

-- coming soon