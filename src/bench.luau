--!strict
--!native
--!optimize 2

-- @rvy
-- bench.mark had to exist

local analyzer = require(script.Parent.analyzer)
local cli = require(script.Parent.cli)
local profiler = require(script.Parent.profiler)
local run = require(script.Parent.run)

local bench = {}

bench.mark = profiler.mark
bench.done = profiler.done
bench.on = profiler.on
bench.off = profiler.off
bench.dump = profiler.dump
bench.abort = profiler.abort
bench.debug = profiler.debug

bench.analyze = analyzer.analyze
bench.compare = analyzer.compare
bench.prune = analyzer.prune

bench.cli = cli
bench.run = run

return bench
