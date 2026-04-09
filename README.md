# barg

**Fast, declarative argument parsing for bash scripts — no dependencies, no subshells.**

`barg` is a pure bash argument parser built for scripts that deserve a proper CLI. Sub-30ms parsing, rich type support, auto-generated help, and shell completions — no dependencies, no subshells.

> **See it in practice:** Real-world usage in [kitsh](https://github.com/klapptnot/kitsh) scripts.

## Features

- **Fast**: Sub-30ms parsing with zero subshells
- **Auto-generated help**: Colored, formatted output with no boilerplate
- **Rich types**: Strings, integers, floats, flags, vectors, and choice validation
- **Zero dependencies**: Pure bash built-ins only
- **Subcommands**: Full subcommand support with per-command options
- **Color theming**: GCC_COLORS-style palette customization
- **Shell completions**: Context-aware completions for Nushell and TSV format
- **Flag bundling**: POSIX-style `-abc` shorthand and numeric suffixes

## Quick Start

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

## Flag Bundling

`barg` supports POSIX-style flag bundling:

```bash
# These are equivalent:
myapp -abc value
myapp -a -b -c value

# Numeric suffixes work too:
myapp -t2        # Same as: myapp -t 2
myapp -v4        # Same as: myapp -v 4
```

## Syntax Reference

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

# Integer (also available: float, num — accepts either)
c/count :int => COUNT "Number of items"

# Arrays (repeatable -t/--tag)
t/tag :strs => TAGS "Tags (can be repeated)"
```

### Choice Validation

```bash
l/level ["debug" "info" "warn" "error"] => LOG_LEVEL "Log level, (def: debug)"
# Choice with a default value
p/priority ["low" "normal" "high"] "normal" => PRIORITY "Task priority"
```

#### Completion Labels for Choices

By default, completions for choice arguments show a generic `"value for --flag"` description. You can override this per-value by declaring a `BARG_SET_LABELS_<VARNAME>` array before calling `barg::parse`, where each index corresponds to the matching choice value:

```bash
# Choices: debug=0, info=1, warn=2, error=3
BARG_SET_LABELS_LOG_LEVEL=(
  "Verbose output, all events"
  "Normal operational messages"
  "Non-fatal issues worth attention"
  "Failures only"
)

barg::parse "${@}" << BARG
l/level ["debug" "info" "warn" "error"] => LOG_LEVEL "Log level"
BARG
```

Completions will show each label instead of the fallback description.

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

# Subcommand-specific options (@<n>)
@install u/update :flag => UPDATE_FIRST "Update before install"
@remove k/keep-config :flag => KEEP_CONFIG "Keep configuration files"
```

### Switches

Switches are mutually exclusive option groups where selecting one sets a specific value:

```bash
# Required mode switch — errors if not provided
! "work-mode" {
  l/list: "list" h"List stuff"
  g/get: "download" h"Download stuff"
  r/remove: "remove" h"Remove stuff"
} => OP_MODE

# COLOR will contain the respective color for --red, --green, or --blue, or default to white
{red: "#ff0000" green: "#00ff00" blue: "#0000ff"} "#ffffff" => COLOR
```

## Dynamic Shell Completions

`barg` generates context-aware completions directly from your argument definitions.

### Supported Formats

#### Nushell
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

#### TSV
```bash
# Get tab-separated completions
myapp @tsvcomp myapp --verb
# Output format: <option>\t<color_code>\t<description>
```

TSV format is designed for building custom shell compatibility layers. Only Nushell has official built-in support due to its rich completion features.

**Basic bash example:**
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

> Tab characters may display as `^I` in some terminals. Users can build more sophisticated wrappers using the color codes and type information for custom formatting.

### How Completions Work

- Subcommand suggestions with descriptions when no subcommand is present
- Flag completions filtered by what's already been used
- Enum value suggestions when completing an argument that accepts specific values
- Color-coded priorities: subcommands (0), optional flags (1), required flags (2), enum values (3)

```bash
# After typing `myapp --level `, completions show: debug, info, warn, error
# After using `-f`, it won't suggest `-f` again
```

### Standalone Completion Scripts

`barg` can serve as a completions backend for any external command — no argument parsing logic required. Write a small script that only declares the interface and outputs completions, then wire it up to your shell.

```bash
#!/usr/bin/bash
source ~/.local/lib/barg.sh

barg::parse @nucomp "${@}" << BARG
meta {
  argv_zero: "git"
  summary: "The stupid content tracker"
}

commands {
  clone:  'Clone a repository'
  commit: 'Record changes to the repository'
  push:   'Update remote refs'
  pull:   'Fetch and integrate with another repository'
}

@commit m/message :str => MESSAGE "Commit message"
@commit a/all     :flag => ALL     "Stage all tracked files"
@push   f/force   :flag => FORCE   "Force push"
BARG
```

Drop this file somewhere accessible and point your shell at it. For Nushell, the `~/.local/comp/` convention works well — one file per command, named after the command:

```nushell
let carapace_completer = {|spans|
  # ... carapace first, then fall back to barg completion scripts
  let comp_f = ([~/.local/comp/ $spans.0] | path join)
  if ($comp_f | path exists) {
    let comp_f = ($comp_f | path expand)
    return (^$comp_f @nucomp ...$spans | from json)
  }
}
```

The script does nothing except emit completions — no argument validation, no side effects, no main logic. Just the declaration.

### Disabling Completions

```bash
meta {
  completion_enabled: false
}
```

## Error Handling

`barg` emits contextual error messages:

```console
$ myapp # Missing required subcommand
ERROR: myapp -> Missing subcommand... A subcommand is required, one of:
  - scan    Scan network for devices
  - ping    Ping multiple hosts

$ myapp --level invalid # Invalid choice
ERROR: myapp -> Invalid parameter value... Argument of --level must be between: debug, info, warn, or error
```

Custom error handler:

```bash
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

Use the built-in error handler in your own validation logic:

```bash
barg::parse "${@}" << BARG
# ... definitions ...
BARG

if [[ -n "$FILES" && -n "$DIR" ]]; then
  barg::exit_msg "Conflicting options" "Cannot use both --files and --directory"
fi

if [[ -z "$FILES" && -z "$DIR" ]]; then
  barg::exit_msg "Missing input" "Either --files or --directory is required"
fi
```

## No Arguments Handling

By default, `barg` returns 1 if no arguments are passed (otherwise always 0):

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

## Configuration

The `meta` block configures global behavior:

<details>
<summary>All meta properties</summary>

### Core Settings

- **argv_zero**: Program name in error messages and help (default: `basename "${0}"`)
  - Example: `argv_zero: "myapp"`

- **summary**: Short tool description shown in help
  - Example: `summary: "A tool to process files"`

### Argument Handling

- **spare_args_var**: Variable name for positional/spare arguments (default: `BARG_SPARE_ARGS`)
  - Example: `spare_args_var: "FILES"`
  - Also creates `${spare_args_var}_COUNT` with the count

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

- **color_palette**: Color scheme, use `:` to disable (default: empty)
  - Example: `color_palette: "38;5;9:38;5;50:38;5;230:38;5;203:38;5;85:38;5;230"`
  - Format: `acc:cmd:req:err:str:any` (6 ANSI codes)

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

## Color Customization

Set globally via the `BARG_COLOR_PALETTE` env var, or per-script via `color_palette` in `meta` (takes priority).

```bash
meta {
  color_palette: '38;5;9:38;5;50:38;5;122:38;5;203:38;5;85:38;5;230'
}
```

Color slots (in order):

1. `acc` — Accents, types, highlights in help
2. `cmd` — Command/program name in help
3. `req` — Required flags in help
4. `err` — Error messages
5. `str` — String default values
6. `any` — Other default values (numbers, booleans)

To disable colors completely: `palette: ":"`

## Performance

`barg` maps flags to value indices for O(1) lookups instead of O(n) string scanning:

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

## Advanced Examples

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

## Comparisons

### vs getopts

**Before:**
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

**After:**
```bash
barg::parse "${@}" << BARG
meta { help_enabled: true }
f/force :flag => FORCE "Force operation"
o/output :str => OUTPUT "Output file"
v/verbose :flag => VERBOSE "Verbose mode"
BARG
```

### vs manual parsing

**Before:**
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

**After:**
```bash
barg::parse "${@}" << BARG
f/force :flag => FORCE "Force operation"
o/output :str => OUTPUT "Output file"
BARG
```

## Variables and Cleanup

### Exported Variables

After parsing, `barg` sets:

- **`BARG_SUBCOMMAND`**: The selected subcommand (empty if none)
- **`BARG_ARGV_TABLE`**: Tracks which variables were explicitly set via CLI
  - `BARG_ARGV_TABLE[VAR_NAME]` is `"!"` if the user provided the value
  - Empty if the value came from a barg default
- **`${spare_args_var}`**: Array of positional arguments (default name: `BARG_SPARE_ARGS`)
- **`${spare_args_var}_COUNT`**: Count of positional arguments
- All variables defined via `=> VAR_NAME`

#### Priority System (CLI > Config > Default)

```bash
@ t/timeout :num 5 => PROC_TIMEOUT "Seconds to wait for response"

# After parsing, PROC_TIMEOUT always has a value (user-provided or default: 5)

# Override with config only if the user didn't set it on CLI
[[ -z "${BARG_ARGV_TABLE[PROC_TIMEOUT]}" && -n "${THIS_CONFIG[timeout]}" ]] \
  && PROC_TIMEOUT="${THIS_CONFIG[timeout]}"

# Result: CLI > config file > barg default
```

### Cleanup

Call `barg::unload` after parsing to remove internal state:

```bash
barg::parse "${@}" << BARG
# ... definitions ...
BARG
barg::unload  # Removes all barg functions and internal variables
# BARG_SUBCOMMAND, BARG_ARGV_TABLE, and spare args variables are preserved
```

## License

MIT — see LICENSE for details.

---
