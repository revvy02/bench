local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_jest-runner@3.10.0"):FindFirstChild("jest-runner"))
export type Test  = module.Test 
export type TestEvents  = module.TestEvents 
export type TestFileEvent  = module.TestFileEvent 
export type OnTestFailure  = module.OnTestFailure 
export type OnTestStart  = module.OnTestStart 
export type OnTestSuccess  = module.OnTestSuccess 
export type TestWatcher  = module.TestWatcher 
export type TestRunnerContext  = module.TestRunnerContext 
export type TestRunnerOptions  = module.TestRunnerOptions 
export type TestRunner  = module.TestRunner 
return module