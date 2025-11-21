# jestir

CLI companion for [jest-luau](https://github.com/jsdotlua/jest-lua). Run your tests in your current Studio session, via Roblox Cloud execution, or by opening a new place file - all routes results back to the CLI.

Requires [rir3](https://github.com/revvy02/rir3) for `--target once` and `--target serve`.

## Installation

Install via [pesde](https://pesde.daimond113.com/):

```bash
pesde add rvy/jestir
```

## Features

- Run tests in Roblox Studio via `rir3 once` (one-time execution, like run-in-roblox)
- Run tests in Roblox Studio via `rir3 serve/exec` (executes in your current Studio session)
- Run tests in Roblox Cloud via Open Cloud API
- Filter tests by name or path patterns
- Support for multiple project configurations
- Configuration via `jestir.toml` and environment variables
- Output control with `--no-error` and `--no-warn` flags

## Usage

Run `jestir` to execute tests in your current Studio session (serve mode). Use the `--target` flag to specify a different execution method.

### Targets

#### `--target once`
Runs tests via `rir3 once` - similar to run-in-roblox. Clones the place file to `.jestir/` temp directory and always opens a fresh Studio instance for testing. **Requires rir3 to be installed.**

**Note:** You must build/maintain the place file yourself - jestir does not build it.

```bash
# Run all tests via rir3 once
jestir --target once

# Run with test filtering
jestir --target once --test-name-pattern "async" --project shared

# Specify custom place file
jestir --target once --place my-test.rbxl
```

#### `--target serve`
Executes tests in your current Studio session via `rir3 exec`. Assumes `rir3 serve` is already running and connected to Studio. Does not build or clone place files. **Requires rir3 to be installed and running.**

```bash
# Run all tests via rir3 exec
jestir --target serve

# Run specific tests
jestir --target serve --test-path-pattern "use_async"
```

#### `--target cloud`
Runs tests in Roblox Cloud using the Open Cloud Luau Execution API. Requires universe ID, place ID, place version, and API key.

```bash
# Run tests in cloud (using jestir.toml config)
jestir --target cloud

# Upload place file and run tests in cloud (uses returned version)
jestir --target cloud --upload

# Override config with CLI flags
jestir --target cloud --universe-id <id> --place-id <id> --place-version <version> --api-key <key>

# Run specific project in cloud
jestir --target cloud --project shared
```

**Cloud Configuration:**
- API key: `--api-key` flag, `JESTIR_API_KEY` environment variable, or `.env` file
- Universe ID: `--universe-id` flag or `jestir.toml` `[cloud]` section
- Place ID: `--place-id` flag or `jestir.toml` `[cloud]` section
- Place Version: `--place-version` flag or `jestir.toml` `[cloud]` section (optional if `--upload` is used)
- Upload: `--upload` flag or `jestir.toml` `[cloud]` section (uploads place file and uses returned version)
- Place File: `--place` flag or `jestir.toml` `[once.place_file]` section (required when using `--upload`)

### Filtering Tests

```bash
# Filter by test name (matches test descriptions)
jestir --target once --test-name-pattern "should handle errors"

# Filter by test file path
jestir --target serve --test-path-pattern "use_async"

# Combine filters
jestir --target once --test-name-pattern "user" --test-path-pattern "auth"
```

### Output Control

Jestir provides flags to control rir3 output verbosity for `once` and `serve` targets:

```bash
# Suppress error and info output from rir3
jestir --target serve --no-error

# Suppress warning output from rir3
jestir --target once --no-warn

# Combine flags for minimal output
jestir --target serve --no-error --no-warn
```

**Output Flags:**
- `--no-error`: Suppresses error and info messages from rir3
- `--no-warn`: Suppresses warning messages from rir3
- These flags only affect rir3's internal output, test results are still shown

### Project Configuration

Create a `jestir.toml` file in your project root:

```toml
[once]
place_file = "test.rbxl"  # Also used by --target cloud when --upload is enabled

[cloud]
place_id = 72824109308551
universe_id = 8612861022
place_version = 51  # Optional if upload is true
upload = false

[projects]
shared = "src/shared"
client = "src/client"
server = "src/server"
hooks = "src/client/app/hooks"
```

**Configuration Details:**
- `[once].place_file`: Path to your built place file for `--target once` and `--target cloud --upload`
- `[cloud].place_id`: Roblox place ID for cloud execution
- `[cloud].universe_id`: Roblox universe ID for cloud execution
- `[cloud].place_version`: Specific place version to run tests against (optional if upload is true)
- `[cloud].upload`: Upload the place file before running tests (default: false)
- `[projects]`: Named project paths that can be referenced with `--project` flag

**Environment Variables:**
- `JESTIR_API_KEY`: Roblox Open Cloud API key (alternative to `--api-key` flag)

You can also create a `.env` file in your project root:

```env
JESTIR_API_KEY=your-api-key-here
```

Then use project names to run specific projects:

```bash
jestir --target once --project shared
```

### Examples

```bash
# Run tests in serve mode (default - connects to current Studio session)
jestir

# Run specific project in serve mode
jestir --project shared

# Filter tests in serve mode
jestir --test-path-pattern "use_async"

# Run all tests via rir3 once (opens new Studio instance)
jestir --target once

# Run tests in cloud (using jestir.toml)
jestir --target cloud

# Upload place file and run tests in cloud
jestir --target cloud --upload

# Filter by test name
jestir --target once --test-name-pattern "async"

# Suppress rir3 errors and warnings
jestir --no-error --no-warn

# Verbose output
jestir --verbose

# CI mode
jestir --target cloud --ci

# Combined: upload, filter, and suppress output
jestir --target cloud --upload --project shared --no-error
```

