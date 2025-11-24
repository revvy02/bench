local process = require("@lune/process") :: any

process.exec("rojo", { "build", "test.project.json", "-o", "test.rbxl" }, { stdio = "forward" })
process.exec("rojo", { "sourcemap", "test.project.json", "-o", "sourcemap.json" }, { stdio = "forward" })
process.exec("jest-rodeo", { "--target", "cloud", "--place", "test.rbxl", "--upload" }, { stdio = "forward" })
