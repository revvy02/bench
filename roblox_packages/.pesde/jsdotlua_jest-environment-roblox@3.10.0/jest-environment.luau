local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_jest-environment@3.10.0"):FindFirstChild("jest-environment"))
export type EnvironmentContext  = module.EnvironmentContext 
export type ModuleWrapper  = module.ModuleWrapper 
export type JestEnvironment<Timer = any> = module.JestEnvironment<Timer >
export type Module  = module.Module 
export type Jest  = module.Jest 
return module