local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_jest-mock@3.10.0"):FindFirstChild("jest-mock"))
export type MaybeMockedDeep<T> = module.MaybeMockedDeep<T>
export type MaybeMocked<T> = module.MaybeMocked<T>
export type UnknownFunction  = module.UnknownFunction 
export type Mock<T = UnknownFunction> = module.Mock<T >
export type ModuleMocker  = module.ModuleMocker 
export type JestFuncFn  = module.JestFuncFn 
export type JestFuncMocked  = module.JestFuncMocked 
export type JestFuncSpyOn  = module.JestFuncSpyOn 
return module