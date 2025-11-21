--!strict
--!native
--!optimize 2

-- @rvy
-- bench.mark had to exist

local analyzer = require(script.Parent.analyzer)
local format = require(script.Parent.format)
local profiler = require(script.Parent.profiler)
local run = require(script.Parent.run)

local bench = {}

bench.mark = profiler.mark
bench.done = profiler.done
bench.on = profiler.on
bench.off = profiler.off
bench.dump = profiler.dump
bench.abort = profiler.abort

bench.analyze = analyzer.analyze
bench.compare = analyzer.compare

bench.format = format
bench.run = run

return bench
