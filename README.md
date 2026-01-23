# barg 🚀

**Blazing fast argument parsing for bash scripts with zero dependencies**

`barg` is a pure bash argument parser that delivers professional CLI experiences with sub-20ms performance. No subshells, no external dependencies, less than 700 lines of optimized bash that transforms how you build command-line tools.

> **See real daily-use examples:** Check out usage in [kitsh](https://github.com/klapptnot/kitsh) scripts.

## ✨ Features

- **⚡ Lightning Fast**: Sub-30ms parsing with zero subshells
- **🎨 Beautiful Help**: Auto-generated help with colors and formatting
- **🔧 Rich Types**: Support for strings, integers, floats, flags, vectors, and choice validation
- **📦 Zero Dependencies**: Pure bash with only built-in commands
- **🎯 Subcommands**: Full subcommand support with per-command options
- **🌈 Customizable Colors**: GCC_COLORS-style theming
- **🔄 Dynamic Completions**: Context-aware shell completions for Nushell and TSV format
- **💪 Advanced Features**: Flag bundling (`-abc`), epilogs, switches, and more

## 🚀 Quick Start

```bash
#!/usr/bin/bash
# file main.sh
source barg.sh

function main {
  barg::parse "${@}" << BARG || { echo "Usage: $0 [OPTIONS] files..." && exit 1; }
  meta {
    summary: "Process files with various options"
    spare_args_var: 'FILES'
    help_enabled: true
    spare_args_required: true
  }

  f/force :flag => FORCE "Force overwrite existing files"
  ! o/output :str => OUTPUT "Output directory"
  v/verbose :flag => VERBOSE "Enable verbose output"
  t/type ["json" "yaml" "xml"] => FORMAT "Output format"
BARG
  barg::unload

  echo "Processing ${#FILES[@]} files with format: ${FORMAT}"
}

main "${@}"
```

**Generated help output:**
```
main.sh: Process files with various options

Usage:
 main.sh [OPTIONS] [...]

Options:
  -h, --help                   flag Show this help message and exit
  -f, --force                  flag Force overwrite existing files
  -o, --output                <str> Output directory
  -v, --verbose                flag Enable verbose output
  -t, --type                   enum Output format
```

## 🔧 Flag Bundling

`barg` supports POSIX-style flag bundling:

```bash
# These are equivalent:
myapp -abc value
myapp -a -b -c value

# Numeric suffixes work too:
myapp -t2        # Same as: myapp -t 2
myapp -v4        # Same as: myapp -v 4
```

## 📖 Syntax Reference

The (abstract and) basic syntax form is the following:

```bnf
declaration ::= <scope>? "!"? <option> <type>? <default>? "=>" <var> <desc>?
scope ::= "@" <identifier>?
option ::= <short>? <long> | <long> | <string>? "{" <entries> "}" | "[" <value> "]"
entries ::= <short>? <long> ":" <string> <help>
help ::= "h" <string>
value ::= <string> | <number> | <boolean>
short ::= <char> "/"
type ::= ":" (("str" | "int" | "num" | "float") "s"? | "flag" )
```

### Basic Options

```bash
# Flag (boolean)
f/force :flag => FORCE_OPR

# Flag (toggled default value)
M/monochrome :flag true => COLORED_OUTPUT "Disable colored output"

# Required string argument (! before flag pattern)
! o/output :str => OUTPUT "Output file path"

# String with default value
n/name :str "default" => NAME "Your name"

# Integer (also available float, and num, which is any of both)
c/count :int => COUNT "Number of items"

# Arrays (repeatable -t/--tag)
t/tag :strs => TAGS "Tags (can be repeated)"
```

### Choice Validation

```bash
# Single choice ("debug" as implicit default)
l/level ["debug" "info" "warn" "error"] => LOG_LEVEL "Log level, (def: debug)"

# Choice with explicit default
p/priority ["low" "normal" "high"] "normal" => PRIORITY "Task priority"
```

### Subcommands

```bash
meta {
  help_enabled: true
}

commands {
  # Mark subcommands that require spare arguments (the * at the start)
  *install: 'Install packages'
  *remove: 'Remove packages'
  help: 'Show help'
}

# Global options (available with or without subcommands)
f/force :flag => FORCE "Force operation"

# A flag only available when no subcommand has been found (the @ at the start)
@ V/version :flag => SHOW_VERSION "Show version and exit"

# Subcommand-specific options (@<name>)
@install u/update :flag => UPDATE_FIRST "Update before install"
@remove k/keep-config :flag => KEEP_CONFIG "Keep configuration files"
```

### Switches

Switches are mutually exclusive option groups where selecting one sets a specific value:

```bash
# Required mode switch - no default value will be set, error if missing
# The value at the right will be set to the variable name (OP_MODE)
! "work-more" {
  l/list: "list" h"List stuff"
  g/get: "download" h"Download stuff"
  r/remove: "remove" h"Remove stuff"
} => OP_MODE

# COLOR will contain the respective color for --red, --green, or --blue, or default to white
{red: "#ff0000" green: "#00ff00" blue: "#0000ff"} "#ffffff" => COLOR
```

## 🎯 Dynamic Shell Completions

`barg` provides **context-aware completions** that automatically generate based on your argument definitions. The completions are intelligent and adapt to the current parsing state.

### Supported Formats

#### Nushell Completions
```bash
let carapace_completer = {|spans|
  let carap_comp = (carapace $spans.0 nushell ...$spans)
  if $carap_comp != '[]' and $carap_comp != '' {
    return ($carap_comp | from json)
  }
  if (barg-comp-allowed $span.0) {
    let completions = (^$spans.0 @nucomp ...($spans))
    if $completions != '[]' {
      return ($completions | from json)
    }
  }
}
```

#### TSV Completions
```bash
# Get tab-separated completions
# Easy to setup for your default shell
myapp @tsvcomp myapp --verb
# Output format: <option>\t<color_code>\t<description>
```

**Purpose**: TSV format is designed for users to create their own shell compatibility layers. Only Nushell has official built-in support due to its rich completions features.

**Working Bash Example** (basic implementation):
```bash
_my_app_completion() {
  local cur prev words cword
  _init_completion || return

  # TSV output: <value>\t<color>\t<desc>
  mapfile -t COMPREPLY < <(my-app @tsvcomp "${words[@]}")

  # Bash (readline) doesn't support descriptions natively
  # Keep full TSV line until selected, then extract just the value
  if [[ "${#COMPREPLY[@]}" == 1 ]]; then
    COMPREPLY=("${COMPREPLY[0]%%$'\t'*}")
  fi
}
complete -F _my_app_completion my-app
```

> **Note**: This bash example is basic. The tab characters may display as `^I` in some contexts. Users can build more sophisticated wrappers using the color codes and type information for custom formatting.

### How It Works

The completion system is context-aware and provides:
- **Subcommand suggestions** with descriptions when no subcommand is present
- **Flag completions** filtered by what's already been used
- **Enum value suggestions** when completing an argument that accepts specific values
- **Color-coded priorities**: subcommands (0), optional flags (1), required flags (2), enum values (3)

```bash
# Example: After typing `myapp --level `
# Completions will show: debug, info, warn, error

# Example: After using `-f`, it won't suggest `-f` again
# but will suggest other available options
```

### Disabling Completions

```bash
meta {
  completion_enabled: false  # Disable dynamic completions
}
```

## 📋 Error Handling

`barg` provides contextual error messages:

```console
$ myapp # Missing required subcommand
ERROR: myapp -> Missing subcommand... A subcommand is required, one of:
  - scan    Scan network for devices
  - ping    Ping multiple hosts

$ myapp --level invalid # Invalid choice
ERROR: myapp -> Invalid parameter value... Argument of --level must be between: debug, info, warn, or error
```

These behaviors can be customized:

```bash
# Custom error handler (return 0 to ignore error, or exit with code)
on_arg_err() {
  echo "Argument error: ${1}"
  echo "${2}"
  return 32 # same as `exit 32`
}

barg::parse "${@}" << BARG
meta {
  help_enabled: true
  on_error: "on_arg_err"
}
BARG
```

### Using `barg::exit_msg`

You can use the built-in error handler in your own validation logic:

```bash
barg::parse "${@}" << BARG
# ... definitions ...
BARG

# Custom validation
if [[ -n "$FILES" && -n "$DIR" ]]; then
  barg::exit_msg "Conflicting options" "Cannot use both --files and --directory"
fi

if [[ -z "$FILES" && -z "$DIR" ]]; then
  barg::exit_msg "Missing input" "Either --files or --directory is required"
fi
```

## 🔄 No Arguments Handling

By default, `barg` returns 1 if no arguments are passed (otherwise always 0), allowing scripts to handle this case:

```bash
barg::parse "${@}" << BARG || { echo "Usage: $0 [OPTIONS]" && exit 1; }
meta {
  help_enabled: true
}
BARG
```

Use `#[always]` to process even with no args:

```bash
barg::parse "${@}" << BARG # Always returns 0, even with no arguments
#[always]
meta {
  help_enabled: true
}
BARG
```

## 🎨 Configuration

The `meta` block configures global behavior:

<details>
<summary>Click to expand all meta properties</summary>

### Core Settings

- **argv_zero**: Program name in error messages and help (default: `basename "${0}"`)
  - Example: `argv_zero: "myapp"`

- **summary**: Short tool description shown in help
  - Example: `summary: "A tool to process files"`

### Argument Handling

- **spare_args_var**: Variable name to store positional/spare arguments (default: `BARG_SPARE_ARGS`)
  - Example: `spare_args_var: "FILES"`
  - Also creates `${spare_args_var}_COUNT` variable with the count

- **spare_args_required**: Require trailing positional arguments (default: `false`)
  - Example: `spare_args_required: true`

- **subcommand_required**: Require a subcommand to be specified (default: `false`)
  - Example: `subcommand_required: true`

- **allow_empty_values**: Allow empty string values for required parameters (default: `false`)
  - Example: `allow_empty_values: true`

### Display & Output

- **help_enabled**: Enable help message generation (default: `false`)
  - Example: `help_enabled: true`

- **show_defaults**: Show default values in help and completions (default: `false`)
  - Example: `show_defaults: true`

- **epilog_lines**: Array variable name containing epilog text lines (default: `""`)
  - Example: `epilog_lines: "EPILOG_TEXT"`
  - Use `{acc}` placeholder for accent color in epilog text

- **quiet_exit**: Suppress console output (default: `false`)
  - Example: `quiet_exit: true`

- **use_stderr**: Use stderr for output/errors (default: `true`)
  - Example: `use_stderr: false`

### Customization

- **color_palette**: Error message color scheme, use `:` for no colors (default: empty)
  - Example: `color_palette: "38;5;9:38;5;50:38;5;230:38;5;203:38;5;85:38;5;230"`
  - Format: `acc:cmd:req:err:str:any` (6 color codes)

- **on_error**: Function name to call on error (default: `""`)
  - Example: `on_error: "on_args_err"`
  - Function receives `error_type` and `error_desc` as arguments

### Feature Toggles

- **completion_enabled**: Enable dynamic completion support (default: `true`)
  - Example: `completion_enabled: false`

</details>

### Simple Example

```bash
barg::parse "${@}" << BARG
meta {
  argv_zero: "myapp"
  summary: "Simple file processor"
  spare_args_var: "FILES"
  help_enabled: true
  show_defaults: true
}

v/verbose :flag => VERBOSE "Enable verbose mode"
o/output :str "output.txt" => OUTPUT "Output file"
BARG
```

## 🎨 Color Customization

Can be customized globally using the env-val `BARG_COLOR_PALETTE` with the colon-separated values, but the `color_palette` property has priority.
Customize colors using colon-separated ANSI codes (6 total):

```bash
meta {
  color_palette: '38;5;9:38;5;50:38;5;122:38;5;203:38;5;85:38;5;230'
}
```

Color mapping (in order):
1. `acc`: Accents for help message, types, highlights
2. `cmd`: Command/program name color in help
3. `req`: Required flags color in help
4. `err`: Error message colors
5. `str`: String default values color
6. `any`: Other default values color (numbers, booleans)

To disable colors completely: `palette: ":"`

## ⚡ Performance

`barg` maps flags to value indices for O(1) flag lookups instead of O(n) string parsing:

```bash
# Internal representation
declare -a argv=([0]="--output" [1]="file.txt" [2]="-v")
declare -A BARG_ARGV_TABLE=([--output]="1" [-v]="3")
```

**Benchmarks:**
- Simple script: ~15ms
- Complex tool (32+ flags): ~25ms
- Zero subshells, pure bash built-ins

### Key Optimizations

- Single regex pass for argument normalization
- Hash table lookups for flag resolution
- No external processes or subshells
- Efficient string manipulation using bash built-ins

## 🛠️ Advanced Examples

<details>
<summary>File Processing Tool</summary>

```bash
#!/usr/bin/bash
source barg.sh

barg::parse "${@}" << BARG
meta {
  summary: "Bulk file rename utility"
  spare_args_var: 'PATTERN'
  help_enabled: true
  spare_args_required: true
}

f/files :strs => FILES "Files to process"
d/directory :str => DIR "Directory to scan"
p/prefix :str => PREFIX "Add prefix to filename"
s/suffix :str => SUFFIX "Add suffix to filename"
n/dry-run :flag => DRY_RUN "Show what would happen"
r/recursive :flag => RECURSIVE "Process subdirectories"
BARG

# Validation
[[ -n "$FILES" && -n "$DIR" ]] &&
  barg::exit_msg "Conflicting options" "Cannot use both {acc}--files{r} and {acc}--directory{r}"

[[ -z "$FILES" && -z "$DIR" ]] &&
  barg::exit_msg "Missing input" "Either {acc}--files{r} or {acc}--directory{r} is required"

barg::unload

# Your processing logic here
```

</details>

<details>
<summary>Network Tool with Subcommands</summary>

```bash
#!/usr/bin/bash
source barg.sh

barg::parse "${@}" << BARG
meta {
  summary: "Network utility toolkit"
  help_enabled: true
  subcommand_required: true
}

commands {
  scan: 'Scan network for devices'
  ping: 'Ping multiple hosts'
  trace: 'Traceroute with options'
}

# Global options
v/verbose :flag => VERBOSE "Verbose output"
t/timeout :int 5 => TIMEOUT "Timeout in seconds"

# Scan-specific options
@scan p/port :ints => PORTS "Ports to scan"
@scan r/range :str => IP_RANGE "IP range (e.g., 192.168.1.1/24)"

# Ping-specific options
@ping c/count :int 4 => PING_COUNT "Number of pings"
@ping i/interval :str 1 => PING_INTERVAL "Interval between pings"
BARG
barg::unload

# Execute based on subcommand
case "$BARG_SUBCOMMAND" in
  scan)
    echo "Scanning ${IP_RANGE} on ports: ${PORTS[*]}"
    ;;
  ping)
    echo "Pinging ${PING_COUNT} times with ${PING_INTERVAL}s interval"
    ;;
  trace)
    echo "Running traceroute with ${TIMEOUT}s timeout"
    ;;
esac
```

</details>

<details>
<summary>Application with Epilog and Help</summary>

```bash
#!/usr/bin/bash
source barg.sh

EPILOG_TEXT=(
  ""
  "{acc}Examples{r}:"
  "  myapp -v process file1.txt file2.txt"
  "  myapp --format json --output results/ *.txt"
  ""
  "{acc}For more information, visit: https://example.com{r}"
)

barg::parse "${@}" << BARG
meta {
  summary: "Advanced file processor"
  spare_args_var: "FILES"
  help_enabled: true
  epilog_lines: "EPILOG_TEXT"
  show_defaults: true
}

v/verbose :flag => VERBOSE "Enable verbose output"
f/format ["json" "yaml" "xml"] "json" => FORMAT "Output format"
o/output :str "." => OUTPUT_DIR "Output directory"
BARG

barg::unload
```

</details>

## 🎯 Comparisons

### From getopts

**Before (getopts):**
```bash
while getopts "f:o:vh" opt; do
  case $opt in
    f) FORCE=true ;;
    o) OUTPUT="$OPTARG" ;;
    v) VERBOSE=true ;;
    h) show_help; exit 0 ;;
  esac
done
```

**After (barg):**
```bash
# No need for manual `show_help` function
barg::parse "${@}" << BARG
meta { help_enabled: true }
f/force :flag => FORCE "Force operation"
o/output :str => OUTPUT "Output file"
v/verbose :flag => VERBOSE "Verbose mode"
BARG
```

### From manual parsing

**Before (manual):**
```bash
while [[ $# -gt 0 ]]; do
  case $1 in
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done
```

**After (barg):**
```bash
# Automatic validation and error messages
barg::parse "${@}" << BARG
f/force :flag => FORCE "Force operation"
o/output :str => OUTPUT "Output file"
BARG
```

## 🔍 Variables and Cleanup

### Exported Variables

After parsing, `barg` creates these global variables:

- **`BARG_SUBCOMMAND`**: The selected subcommand (empty if none)
- **`BARG_ARGV_TABLE`**: Associative array that tracks which variables were set by the user
  - If `BARG_ARGV_TABLE[VAR_NAME]` is `"!"`, the user provided the value via command line
  - If empty, the value was NOT provided by the user (using the default from barg definition)
- **`${spare_args_var}`**: Array of spare/positional arguments (configurable name, default name `BARG_SPARE_ARGS`)
- **`${spare_args_var}_COUNT`**: Count of spare arguments
- All your defined variables from the `=> VAR_NAME` syntax

#### Example: Priority System (CLI > Config > Default)

```bash
# Option definition with default value
@ t/timeout :num 5 => PROC_TIMEOUT "Number of seconds to wait for response"

# After parsing, PROC_TIMEOUT always has a value (either from user or default: 5)

# Override with config file value ONLY if user didn't provide it on CLI
[[ -z "${BARG_ARGV_TABLE[PROC_TIMEOUT]}" && -n "${THIS_CONFIG[timeout]}" ]] \
  && PROC_TIMEOUT="${THIS_CONFIG[timeout]}"

# Result:
# - If user provided --timeout, PROC_TIMEOUT keeps that value
# - Else if config has timeout, PROC_TIMEOUT uses config value
# - Else PROC_TIMEOUT keeps the default value (5)
```

This pattern enables a clean priority system: **CLI args > config file > barg defaults**

### Cleanup

Always call `barg::unload` after parsing to clean up:

```bash
barg::parse "${@}" << BARG
# ... definitions ...
BARG
barg::unload  # Removes all barg functions and option variables
# BARG_SUBCOMMAND, BARG_ARGV_TABLE, and spare args variables won't be removed

# Your script logic here
```

This unsets all barg-related functions and variables to keep your environment clean.

## 📄 License

MIT License - see LICENSE file for details.

---

<div align="center">Created by <a href="https://github.com/Klapptnot">Klapptnot</a> with ❄️💜🩷🩵</div>

<div align="center"><b>"The fastest argument parser you never knew you needed!"</b> ✨</div>
