# Bench

[![Lint](https://github.com/revvy02/bench/actions/workflows/lint.yml/badge.svg)](https://github.com/revvy02/bench/actions/workflows/lint.yml)
[![Test](https://github.com/revvy02/bench/actions/workflows/test.yml/badge.svg)](https://github.com/revvy02/bench/actions/workflows/test.yml)

A high-performance, composable benchmarking library for Luau with minimal overhead and hierarchical performance tracking.

## Overview

**Key Features:**
- **Composability**: Nest benchmarks and use incremental dumps while maintaining hierarchical measurement relationships
- **Minimal Overhead**: `mark()` and `done()` are extremely fast for usage in hot code paths
- **Topological Awareness**: Scope-aware hierarchical data extraction
- **Rich Analysis**: Statistics, percentiles, comparisons, and nicely formatted output

## Design Philosophy

When comparing implementations (e.g., old vs new algorithm), they often share the same hierarchical structure. To capture this, `mark()` and `done()` sit directly in your code to define and label topology non-intrusively, making it easy to instrument existing code without disrupting flow. Dumps automatically group samples based on their position in the hierarchy, preserving the structural relationships between measurements. This hierarchical grouping becomes the foundation for structure-aware comparison: `compare()` leverages the shared topology to intelligently align implementations by their underlying structure, showing performance deltas at each level of the hierarchy and making it clear exactly where optimizations succeeded or failed.

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
rodeo exec path/to/benchmark.luau

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

### Simulation Testing

```luau
bench.on()
bench.mark("sim test")
  local connection = game:GetService("RunService").Heartbeat:Connect(function()
    bench.mark("step")
    -- simulation logic here
    bench.done()
  end)
  task.wait(10)
  connection:Disconnect()
bench.done()

local dump = bench.dump()
print(bench.cli(bench.analyze(dump["sim test"].children.step)))
-- Shows statistics for all steps over 10 seconds
```

### Implementation Comparison

```luau
bench.on()

bench.mark("old")
  for i = 1, 1000 do
    bench.mark("parse")
    oldParser(data)
    bench.done()
  end
bench.done()
local old_dump = bench.dump()

bench.mark("new")
  for i = 1, 1000 do
    bench.mark("parse")
    newParser(data)
    bench.done()
  end
bench.done()
local new_dump = bench.dump()

-- Compare shows deltas at matching topology
local old_analysis = bench.analyze(old_dump.old.children.parse)
local new_analysis = bench.compare(bench.analyze(new_dump.new.children.parse), { old = old_analysis })
print(bench.cli(new_analysis))
```

### Hierarchical Performance

```luau
bench.on()
bench.mark("frame")
  bench.mark("physics")
  physicsStep()
  bench.done()

  bench.mark("rendering")
    bench.mark("culling")
    frustumCull()
    bench.done()

    bench.mark("draw")
    drawCalls()
    bench.done()
  bench.done()
bench.done()

print(bench.cli(bench.analyze(bench.dump().frame)))
-- Outputs full hierarchy with timing at each level
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