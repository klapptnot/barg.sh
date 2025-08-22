# barg 🚀

**Blazing fast argument parsing for bash scripts with zero dependencies**

`barg` is a pure bash argument parser that delivers professional CLI experiences with sub-20ms performance. No subshells, no external dependencies, less than 700 lines of optimized bash that transforms how you build command-line tools.

## ✨ Features

- **⚡ Lightning Fast**: Sub-20ms parsing with zero subshells
- **🎨 Beautiful Help**: Auto-generated help with colors and formatting
- **🔧 Rich Types**: Support for strings, integers, flags, vectors, and choice validation
- **📦 Zero Dependencies**: Pure bash with only built-in commands
- **🎯 Subcommands**: Full subcommand support with per-command options
- **🌈 Customizable Colors**: GCC_COLORS-style theming
- **💪 Advanced Features**: Flag bundling (`-abc`), epilogs, and more

## 🚀 Quick Start

```bash
#!/usr/bin/bash
# file main.sh
source barg.sh

function main {
  barg::parse "${@}" << BARG || { echo "Usage: $0 [OPTIONS] files..." && exit 1; }
  meta {
    summary: "Process files with various options"
    extargs: 'FILES'
    helpmsg: true
    reqargs: true
  }

  f/force :flag => FORCE "Force overwrite existing files"
  ! o/output :str => OUTPUT "Output directory"
  v/verbose :flag => VERBOSE "Enable verbose output"
  t/type ["json" "yaml" "xml"] => FORMAT "Output format"
BARG
  barg::unload

  echo "Processing ${#FILES[@]} files with format: $FORMAT"
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
  -o, --output                <str> Output directorys
  -v, --verbose                flag Enable verbose output
  -t, --type                        Output format
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
declaration ::= <name>? "!"? <option> <type>? <default>? "=>" <var> <desc>?
name ::= "@" <identifier>?
option ::= <short>? <long> | <long> | "{" {<entries>} "}" | "[" {<value>} "]"
entries ::= <short>? <long> ":" <string>
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
  helpmsg: true
}

commands {
  install: 'Install packages'
  remove: 'Remove packages'
  help: 'Show help'
}

# Global options (with or without subcomands)
f/force :flag => FORCE "Force operation"

# A flag only available when no subcommand has been found (the @ at the start)
@ V/version :flag => SHOW_VERSION "Show version and exit"

# Subcommand-specific options (@<name>)
@install u/update :flag => UPDATE_FIRST "Update before install"
@remove k/keep-config :flag => KEEP_CONFIG "Keep configuration files"
```

### Switches

```bash
# Required mode, flags inside this dont require a value
# the value at the right will be set to the variable name (OP_MODE)
# If none was found, and no default value was set, it will be `0`
! {
  l/list: "list"
  g/get: "download"
  r/remove: "remove"
} => OP_MODE

# COLOR will contain the respective color for --red, --green, or --blue, or default to white
{red: "#ff0000" green: "#00ff00" blue: "#0000ff"} "#ffffff" => COLOR
```


## 📋 Error Handling

`barg` provides contextual error messages:

```console
$ myapp # Missing required subcommand
ERROR: myapp -> Missing subcommand... A subcommand is required, one of:
  - scan    Scan network for devices
  - ping    Ping multiple hosts

$ myapp --level invalid # Invalid choice
ERROR: myapp -> Invalid parameter value... Argument of `--level` must be between: debug, info, warn or error
```

These behavior can be customized like the following

```bash
# return 0 -> ignore error
on_arg_err() {
  echo "Argument error: ${1}"
  echo "${1}"
  return 32 # same as `exit 32`
}
barg::parse "${@}" << BARG ||
meta {
  helpmsg: true
  exitnow: false
  onerrcb: "on_arg_err"
}
BARG
```

## No Arguments Handling

By default, `barg` only returns 1 if no arguments are passed (otherwise always 0), allowing scripts to handle this case:

```bash
barg::parse "${@}" << BARG || { echo "Usage: $0 [OPTIONS]" && exit 1; }
meta {
  helpmsg: true
}
BARG
```

You can use `#[always]` to process even with no args, and maybe combine it with `onerrcb` property for error handling, or to display

```bash
barg::parse "${@}" << BARG # it will always return 0
#[always]
meta {
  helpmsg: true
}
BARG
```

## Configuration

The `meta` block configures global behavior:

<details>
<summary>Click to expand all properties</summary>

- **prognam**: Program name in error messages (default: output of `basename "${0}`")
  - Example: `prognam: "myapp"`

- **palette**: Error message color scheme, fill it with ':' for no colors (default: empty)
  - Example: `palette: "38;5;9:38;5;50"`

- **summary**: Program description (default: "")
  - Example: `summary: "A tool to process files"`

- **onerrcb**: Function name to run on error (default: "")
  - Example: `onerrcb: "on_args_err"`

- **extargs**: Collect positional parameters (default: "")
  - Example: `extargs: "FILES"`

- **epilogs**: Array name for epilog text (default: "")
  - Example: `epilogs: "EPILOG_TEXT"`

- **display**: Print output to console (default: true)
  - Example: `display: false`

- **toerror**: Redirect to stderr (default: true)
  - Example: `toerror: false`

- **helpmsg**: Generate help message (default: false)
  - Example: `helpmsg: true`

- **showdef**: Show defaults in help (default: false)
  - Example: `showdef: true`

- **reqargs**: Require positional args (default: false)
  - Example: `reqargs: true`

- **reqcmds**: Require subcommand (default: false)
  - Example: `reqcmds: true`

- **checkvl**: Allow empty required values (default: false)
  - Example: `checkvl: true`

</details>

Simple example:

```bash
barg::parse "${@}" << BARG
meta {
  prognam: "myapp"
  summary: "Simple file processor"
  extargs: "FILES"
  helpmsg: true
}

v/verbose :flag => VERBOSE "Enable verbose mode"
o/output :str => OUTPUT "Output file"
BARG
```

## 🎨 Color Customization

Customize colors using GCC_COLORS-style syntax:

```bash
meta {
  palette: '38;5;9:38;5;50:38;5;122:38;5;230:38;5;231:38;5;203:38;5;117'
}
```

Color mapping:
- `acc`: Accents for help message
- `err`: Error message colors
- `hil`: Highlightings for the patterns
- `cmd`: Command color in help message
- `req`: Required flags color in help message
- `typ`: Type annotations in help message
- `def`: Word `def` color before the value in help message
- `dsv`: String value color in help message
- `dov`: Other values' colors in help message

## ⚡ Performance

`barg` maps flags to value indices, this enables O(1) flag lookups instead of O(n) string parsing:

```bash
# Internal representation
declare -a argv=([0]="--output" [1]="file.txt" [2]"-v")
declare -A _argv_table=([--output]="1" [-v]="3")
```

**Benchmarks:**
- Simple script: ~15ms
- Complex tool (32+ flags): ~25ms
- Zero subshells, pure bash built-ins

## 🛠️ Simple Examples

<details>
<summary>Click to expand examples</summary>

### File Processing Tool

```bash
barg::parse "${@}" << BARG
meta {
  summary: "Bulk file rename utility"
  extargs: 'PATTERN'
  helpmsg: true
  reqargs: true
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
  barg::exit_msg "Conflicting options" "Cannot use both --files and --directory"

[[ -z "$FILES" && -z "$DIR" ]] &&
  barg::exit_msg "Missing input" "Either --files or --directory is required"
```

### Network Tool with Subcommands

```bash
barg::parse "${@}" << BARG
meta {
  summary: "Network utility toolkit"
  helpmsg: true
  reqcmds: true
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
# Unset all variables and functions after use
barg::unload
```

</details>

## 🎯 Comparations

### From getopts

```bash
while getopts "f:o:vh" opt; do
  case $opt in
    f) FORCE=true ;;
    o) OUTPUT="$OPTARG" ;;
    v) VERBOSE=true ;;
    h) show_help; exit 0 ;;
  esac
done

# No need for `show_help` function
barg::parse "${@}" << BARG
meta { helpmsg: 'true' }
f/force :flag => FORCE "Force operation"
o/output :str => OUTPUT "Output file"
v/verbose :flag => VERBOSE "Verbose mode"
BARG
```

### From manual parsing

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

# no need for descriptions
barg::parse "${@}" << BARG
f/force :flag => FORCE
o/output :str => OUTPUT
BARG
```

## 📄 License

MIT License - see LICENSE file for details.

---

<div align="center">Created by <a href="https://github.com/Klapptnot">Klapptnot</a> with ❄️💜🩷🩵</div>

<div align="center"><bold>"The fastest argument parser you never knew you needed!"</bold> ✨</div>
