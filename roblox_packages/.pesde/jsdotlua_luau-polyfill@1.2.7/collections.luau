local module = require(script.Parent.Parent:FindFirstChild("jsdotlua_collections@1.2.7"):FindFirstChild("collections"))
export type Array<T> = module.Array<T>
export type Map<T, V> = module.Map<T, V>
export type Object  = module.Object 
export type Set<T> = module.Set<T>
export type WeakMap<T, V> = module.WeakMap<T, V>
return module