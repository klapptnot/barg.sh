#!/usr/bin/bash

# Barg - Bash Argument Parser
# ===========================
# Provides argument parsing functionality with:
# - Short and long flags (-f/--flag)
# - Required and optional arguments
# - Argument type validation (string, int, float)
# - Subcommand support
# - Help message generation
# - Dynamic shell completions
# - Argument collections (arrays)
# - Default values
# - Error handling with customizable messages

# Check if this script is being executed as the main script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf "[\x1b[38;05;160m*\x1b[00m] This script is not made to run as a normal script\n"
  exit 1
fi

declare -Ag __barg_opts=(
  [argv_zero]="${0##*/}"      # Program name (from $0)
  [summary]=''                # Short tool description
  [color_palette]=''          # Error message color profile
  [on_error]=''               # Function to call on failure
  [epilog_lines]=''           # Array name for footer/examples
  [spare_args_var]=''         # Variable name to store leftovers
  [spare_args_required]=false # Require trailing positional arguments
  [subcommand_required]=false # Require the second-level command
  [allow_empty_values]=false  # Allow "" for required parameters
  [show_defaults]=false       # Show default values in help
  [help_enabled]=false        # Enable help message generation
  [completion_enabled]=true   # Enable dynamic completions
  [quiet_exit]=false          # Suppress console output
  [use_stderr]=true           # Use stderr for output/errors
)
declare -Ag __barg_palette=(
  [acc]='\x1b[38;5;50m'
  [cmd]='\x1b[38;5;230m'
  [req]='\x1b[38;5;203m'
  [err]='\x1b[38;5;9m'
  [str]='\x1b[38;5;2m'
  [any]='\x1b[38;5;3m'
)
declare -Ag __barg_subcommands=()

function barg::unload {
  unset -f \
    barg::var_exists \
    barg::is_in_arr \
    barg::normalize_args \
    barg::validate_numeric \
    barg::param_set \
    barg::colorize \
    barg::gen_help_message \
    barg::dynamic_completion \
    barg::nucompletion_adapter \
    barg::exit_msg \
    barg::unload

  unset -v __barg_opts __barg_palette __barg_subcommands
}

function barg::nucompletion_adapter {
  local colors=(
    xterm_violet         # for subcommands
    xterm_lightsteelblue # for optional params
    xterm_hotpinka       # for required params
    xterm_plum2          # for enum value
  )
  local s='' res=() o="${IFS}"
  while IFS=$'\t\n' read -r value color desc; do
    value="${value@Q}"            # escape string
    value="${value/#\$/}"         # remove leading $ (if found)
    value="${value:1:-1}"         # remove '...' quotes added
    value="${value//\'\\\'\'/\'}" # remove '\'' no need to escape
    value="${value//\"/\\\"}"     # escape "
    desc="${desc@Q}"
    desc="${desc/#\$/}"
    desc="${desc:1:-1}"
    desc="${desc//\'\\\'\'/\'}"
    desc="${desc//\"/\\\"}"
    printf -v s '{"value":"%s ", "display": "%s", "description": "%s", "style": {"fg": "%s"}}' "${value}" "${value}" "${desc}" "${colors[color]}"
    res+=("${s}")
  done
  IFS=',' s="${res[*]}"
  IFS="${o}"
  printf '[%s]' "${s}"
}

function barg::var_exists {
  declare -p "${1}" &>/dev/null
}

function barg::is_in_arr {
  local item="${1}"
  shift
  for el in "${@}"; do
    [[ "${el}" == "${item}" ]] && return 0
  done
  return 1
}

function barg::normalize_args {
  local i=0
  while ((i < ${#argv[@]})); do
    [[ "${argv[i]}" == '--' ]] && ((i = i + 2)) && continue
    # is flag-like, and is short or long, single char will get removed if not here
    if [[ "${argv[i]}" != -* ]] || [ "${#argv[i]}" -eq 2 ] || [[ "${argv[i]}" == --* ]] || [[ "${argv[i]}" == '-' ]]; then
      ((i++))
      continue
    fi
    if [[ "${argv[i]}" =~ ^-[A-Za-z][0-9_\.]*$ ]]; then # only -t2 (argument and numeric value)
      argv=(
        "${argv[@]:0:i}"           # All before joint argument
        "${argv[i]:0:2}"           # the short argument key
        "${argv[i]:2:${#argv[i]}}" # The content of the argument
        "${argv[@]:(i + 1)}"       # All after joint argument
      )
    else
      argv[i]="${argv[i]:1}"
      local -a __slices__=()
      for ((j = 0; j < ${#argv[i]}; j++)); do
        __slices__+=("-${argv[i]:j:1}")
      done
      if [[ "${#__slices__[@]}" -gt 0 ]]; then
        argv=(
          "${argv[@]:0:i}"     # All before joint argument
          "${__slices__[@]}"   # All individual argument
          "${argv[@]:(i + 1)}" # All after joint argument
        )
      fi
      unset __slices__
    fi
    ((i++))
  done
}

function barg::validate_numeric {
  local value="${1}"
  local type="${2}"

  local regex=""
  local type_name=""

  case "${type}" in
  'num')
    regex="${__num_regex__}"
    type_name="int{r} or {acc}float"
    ;;
  'int')
    regex="${__int_regex__}"
    type_name="integer"
    ;;
  'float')
    regex="${__flt_regex__}"
    type_name="float"
    ;;
  esac

  if ! [[ "${value}" =~ ${regex} ]]; then
    if [[ "${value}" =~ ^[_\.0-9]*$ ]]; then
      barg::exit_msg "Unknown format" "Invalid numerical value, expected a {acc}${type_name}{r} ({any}${value}{r})"
    fi
    barg::exit_msg "Type mismatch" "Expected {acc}${type_name}{r}, got string ({any}${value}{r})"
  fi
}

function barg::param_set {
  local param_sign="${1}"   # short/long :type | short/long [...] | {...}
  local set_var_name="${2}" # VARIABLE (variable name)
  local def_value="${3}"    # Variable default value
  local param_type="${4}"   # Variable value type
  local param_flags="${5}"
  local is_vec_list=false
  local is_required=false
  ((${#param_flags} == 2)) && is_required=true && is_vec_list=true
  [ "${param_flags}" == 's' ] && is_vec_list=true
  [ "${param_flags}" == '!' ] && is_required=true

  ! ${is_vec_list} && barg::var_exists "${set_var_name}" && return 0

  local check_valid_item=false
  if [[ "${param_sign}" == *'}' ]]; then
    local STR="${param_sign:1:-1}"
    STR="${STR#*\{}"
    while [[ "${STR}" =~ ${__obj_regex__} ]]; do
      local short="${BASH_REMATCH[2]}"
      local long="${BASH_REMATCH[3]}"
      local value="${BASH_REMATCH[5]:-${BASH_REMATCH[7]}}"

      if [ -n "${short}" ]; then
        short="-${short:0:-1}"
        long="--${long}"
      else
        (("${#long}" > 1)) && long="--${long}" || {
          short="-${long}"
          long=''
        }
      fi

      if barg::is_in_arr "${short}" "${!BARG_ARGV_TABLE[@]}"; then
        declare -g "${set_var_name}=${value}"
        BARG_TAKEN_ARGS+=("$((${BARG_ARGV_TABLE["${short}"]} - 1))")
        unset "BARG_ARGV_TABLE[${short}]"
      elif barg::is_in_arr "${long}" "${!BARG_ARGV_TABLE[@]}"; then
        declare -g "${set_var_name}=${value}"
        BARG_TAKEN_ARGS+=("$((${BARG_ARGV_TABLE["${long}"]} - 1))")
        unset "BARG_ARGV_TABLE[${long}]"
      else
        STR="${STR/#"${BASH_REMATCH[0]}"/}"
        continue
      fi

      # already set + not needed to continue
      BARG_ARGV_TABLE["${set_var_name}"]="!"
      return
    done
    ${is_required} && barg::exit_msg "Missing required arguments" "${param_type:+"{acc}${param_type}{r} "}switch is a required argument"
    declare -g "${set_var_name}=${def_value:-0}"
    return
  fi

  local maybe_checked_list="${param_sign#*\ }" # :type | [...]
  param_sign="${param_sign%%\ *}"              # short/long

  if [[ "${maybe_checked_list:0:1}" == '[' ]]; then
    check_valid_item=true
    param_type='str'
    local STR="${maybe_checked_list:1:-1}"
    local __valid_items__=()
    while [[ "${STR}" =~ ${__lst_regex__} ]]; do
      local value="${BASH_REMATCH[2]:-${BASH_REMATCH[4]}}"
      __valid_items__+=("${value}")
      STR="${STR/#"${BASH_REMATCH[0]}"/}"
    done
    def_value="${__valid_items__[0]}"
  fi
  unset maybe_checked_list STR

  #shellcheck disable=2178
  local __short__=""
  local __long__=""
  local signat=""

  if [[ "${param_sign}" == ?'/'* ]]; then
    __short__="-${param_sign%/*}"
    __long__="--${param_sign#*/}"
    signat="{acc}${__short__}{r}/{acc}${__long__}{r}"
  else
    (("${#param_sign}" > 1)) && __long__="--${param_sign}" || __short__="-${param_sign}"
    signat="{acc}${__long__:-${__short__}}{r}"
  fi

  # Check if it was found in command line and set its
  # form for the key of the args table, otherwise set default
  if [ -n "${BARG_ARGV_TABLE["${__short__:- }"]}" ]; then
    local the_found_flag="${__short__}"
  elif [ -n "${BARG_ARGV_TABLE["${__long__:- }"]}" ]; then
    local the_found_flag="${__long__}"
  else
    ${is_required} && barg::exit_msg "Missing required arguments" "${signat} is a required argument"
    if [ "${param_type}" == "flag" ]; then
      case "${def_value}" in
      'true' | 'false') declare -g "${set_var_name}=${def_value}" ;;
      *) declare -g "${set_var_name}=false" ;;
      esac
    elif ${is_vec_list}; then
      declare -ag "${set_var_name}=()"
    else
      declare -g "${set_var_name}=${def_value}"
    fi
    return 0
  fi

  # it's supposed to not be found to set default value here
  BARG_ARGV_TABLE["${set_var_name}"]="${the_found_flag}"

  # take last value as valid
  local current_value_index="${BARG_ARGV_TABLE[${the_found_flag}]##*\ }"

  local _added_indexes=()
  if ! ${is_vec_list}; then
    local value="${argv[current_value_index]}"
    case "${param_type}" in
    'flag')
      case "${def_value}" in
      'true') declare -g "${set_var_name}=false" ;;
      *) declare -g "${set_var_name}=true" ;;
      esac
      BARG_TAKEN_ARGS+=("$((current_value_index - 1))")
      ;;
    *)
      if [[ "${value}" == -* ]]; then
        [ "${value}" != '--' ] && barg::exit_msg "Param-like value" "Value for {acc}${the_found_flag}{r} looks like an option/flag. Use {str}'-- ${value}'{r} to bypass"
        value="${argv[current_value_index + 1]}"
        BARG_TAKEN_ARGS+=("$((current_value_index + 1))")
      fi
      if [ "${param_type}" == 'str' ]; then
        declare -g "${set_var_name}=${value}"
      else
        barg::validate_numeric "${value}" "${param_type}"
        declare -g "${set_var_name}=${value//_/}"
      fi
      BARG_TAKEN_ARGS+=("$((current_value_index - 1))" "${current_value_index}")
      ;;
    esac
  else
    IFS=' ' read -ra _any_value_index <<<"${BARG_ARGV_TABLE["${__short__}"]} ${BARG_ARGV_TABLE["${__long__}"]}"
    for index in "${_any_value_index[@]}"; do
      local value="${argv[index]}"
      [ -z "${value}" ] && continue
      if [[ "${value}" == -* ]]; then
        [ "${value}" != '--' ] && barg::exit_msg "Param-like value" "Value for {acc}${argv[index - 1]}{r} looks like an option/flag. Use {str}'-- ${argv[index]}{r} to bypass"
        value="${argv[index + 1]}"
        BARG_TAKEN_ARGS+=("$((index + 1))")
      fi
      if [ "${param_type}" == 'str' ]; then
        declare -ga "${set_var_name}+=(\"${value}\")"
      else
        barg::validate_numeric "${value}" "${param_type}"
        declare -ga "${set_var_name}+=(\"${value//_/}\")"
      fi
      BARG_TAKEN_ARGS+=("$((index - 1))")
    done
    BARG_TAKEN_ARGS+=("${_any_value_index}")
    unset _any_value_index
  fi

  unset "BARG_ARGV_TABLE[${the_found_flag}]"

  ! barg::var_exists "${set_var_name}" && ${is_required} && barg::exit_msg "Missing required arguments" "${signat} is a required argument"

  [ "${__barg_opts[allow_empty_values]}" != 'true' ] &&
    ${is_required} &&
    [ -z "${!set_var_name}" ] &&
    barg::exit_msg "Missing required arguments" "${signat} has an empty value"

  ! barg::var_exists "${set_var_name}" || ! ${check_valid_item} && return
  barg::is_in_arr "${!set_var_name}" "${__valid_items__[@]}" && return

  printf -v items '{acc}%s{r}, ' "${__valid_items__[@]:1}"
  items="${items% *} or {acc}${__valid_items__[0]}{r}"
  barg::exit_msg "Invalid parameter value" "Argument of ${signat} must be between: ${items}"
}

function barg::colorize {
  declare -n string="${1}"
  string="${string//\{r\}/$'\x1b[0m'}"
  local res=""
  while [[ "${string}" =~ \{([a-z_]+)\} ]]; do
    res="${__barg_palette[${BASH_REMATCH[1]}]:-${BASH_REMATCH[0]}}"
    string="${string//"${BASH_REMATCH[0]}"/"${res}"}"
  done
}

# barg::exit_msg <error type> <error desc>
function barg::exit_msg {
  local error_type="${1}"
  local error_desc="${2}"

  local onerrcb="${__barg_opts[on_error]}"
  if [ -n "${onerrcb}" ]; then
    "${onerrcb}" "${error_type}" "${error_desc}" && return || exit ${?}
  fi

  local toerror="${__barg_opts[use_stderr]}"
  local be_quiet="${__barg_opts[quiet_exit]}"
  local prognam="${__barg_opts[argv_zero]}"

  local _err_msg="{err}ERROR: ${prognam} -> ${error_type}...{r} ${error_desc}"
  barg::colorize _err_msg

  if [ "${be_quiet}" != 'true' ]; then
    [ "${toerror}" == 'true' ] && printf '%b\n' "${_err_msg}" >&2 ||
      printf '%b\n' "${_err_msg}"
  fi

  exit 1
}

# barg::gen_help_message <params[@]> <types[@]> <descs[@]> <extargs[@]>
function barg::gen_help_message {
  local -n params="${1}"
  local -n types="${2}"
  local -n descs="${3}"
  local -n flags="${4}"

  local clacc="${__barg_palette[acc]}"
  local clcmd="${__barg_palette[cmd]}"
  local clreq="${__barg_palette[req]}"
  local clstr="${__barg_palette[str]}"
  local clany="${__barg_palette[any]}"

  local prognam="${__barg_opts[argv_zero]}"
  local __all_subcommands=("${!__barg_subcommands[@]}")
  local scmd_str=""
  [[ "${#__all_subcommands[@]}" -gt 0 ]] && {
    [[ -n "${BARG_SUBCOMMAND}" ]] && scmd_str=" ${BARG_SUBCOMMAND}" || scmd_str=" COMMAND"
  }
  if [ -n "${BARG_SUBCOMMAND}" ]; then
    local desc="${__barg_subcommands["${BARG_SUBCOMMAND}"]:-${__barg_subcommands["*${BARG_SUBCOMMAND}"]}}"
    printf '\x1b[1m%b%s\x1b[0m%s\n\n' "${clacc}" "${prognam}" " ${BARG_SUBCOMMAND}${desc:+: ${desc}}"
  elif [ -n "${__barg_opts[summary]}" ]; then
    printf '\x1b[1m%b%s\x1b[0m: %s\n\n' "${clacc}" "${prognam}" "${__barg_opts[summary]}"
  fi

  [[ "${__barg_opts[spare_args_required]}" == true || -n "${__barg_subcommands["*${BARG_SUBCOMMAND}"]}" ]] && local __dummy_bool_extras="-"
  printf '%bUsage\x1b[0m:\n %b%s\x1b[0m%s [OPTIONS]%s\n\n' "${clacc}" "${clcmd}" "${prognam,,}" "${scmd_str}" "${__dummy_bool_extras:+ [...]}"

  if [ -z "${BARG_SUBCOMMAND}" ] && [[ "${#__all_subcommands[@]}" -gt 0 ]]; then
    printf "%bAvailable subcommands\x1b[0m:\n" "${clacc}"
    for sub in "${__all_subcommands[@]}"; do
      printf "  %-16s %s\n" "${sub#\*}" "${__barg_subcommands["${sub}"]}"
    done
    printf '\n'
  fi

  function __print_flag_line {
    local optstr="  "
    if [[ -n "${short}" && -n "${long}" ]]; then
      optstr+="${short}, ${long}"
    elif [[ -n "${short}" ]]; then
      optstr+="${short}"
    elif [[ -n "${long}" ]]; then
      optstr+="    ${long}"
    fi

    if [[ -n "${type}" && "${type}" != "flag" && "${type}" != "switch" ]]; then
      if [ -n "${is_vec}" ]; then
        type="[${type}]"
      elif [ -n "${is_req}" ]; then
        type="<${type}>"
      fi
    fi

    if [[ "${__barg_opts[show_defaults]}" == 'true' && "${type}" != "switch" && -n "${__defaults[i]}" ]]; then
      local default_str="${__defaults[i]}"
      if [[ "${type}" == "str" ]]; then
        # For strings, limit to 45 chars and add  if needed
        [[ ${#__defaults[i]} -gt 45 ]] && default_str="${default_str:0:44}…"
        default_str="${clstr}\"${default_str}\""
      else
        # For nums/bools, show full value
        default_str="${clany}${__defaults[i]}"
      fi
      desc="${desc} (${clacc}def\x1b[0m: ${default_str}\x1b[0m)"
    fi

    [ "${type}" == "switch" ] && type="${name}"

    printf "%b%-25s\x1b[0m %b%10s\x1b[0m %b\x1b[0m\n" "${is_req:+${clreq}}" "${optstr}" "${clacc}" "${type}" "${desc}"
  }

  printf '%bOptions\x1b[0m:\n' "${clacc}"

  local param="" short="" long="" name="" \
    type="" desc="" is_req="" is_vec=""

  local count="${#params[@]}"
  for ((i = 0; i < count; i++)); do
    param="${params[i]}"
    type="${types[i]}"
    desc="${descs[i]}"
    ((${#flags[i]} == 2)) && is_req='!' && is_vec='s'
    [[ "${flags[i]}" == '!' ]] && is_req='!' || is_req=''
    [[ "${flags[i]}" == 's' ]] && is_vec='s' || is_vec=''

    short=""
    long=""
    if [[ "${param}" != *'}' ]]; then
      param="${param%%\ *}"
      if [[ "${param}" == ?'/'* ]]; then
        short="-${param%/*}"
        long="--${param#*/}"
      else
        (("${#param}" > 1)) && long="--${param}" || short="-${param}"
      fi
      __print_flag_line
      continue
    fi

    param="${param:1:-1}"
    param="${param#*\{}"
    name="${type}"
    while [[ "${param}" =~ ${__obj_regex__} ]]; do
      type="switch"
      local short="${BASH_REMATCH[2]}"
      local long="${BASH_REMATCH[3]}"
      local value="${BASH_REMATCH[5]:-${BASH_REMATCH[7]}}"
      local desc="${BASH_REMATCH[12]:-${BASH_REMATCH[14]:-${desc}}}"

      if [ -n "${short}" ]; then
        short="-${short:0:-1}"
        long="--${long}"
      else
        (("${#long}" > 1)) && long="--${long}" || {
          short="-${long}"
          long=''
        }
      fi

      __print_flag_line
      param="${param/#"${BASH_REMATCH[0]}"/}"
    done
  done
  param=""
  short="-h"
  long="--help"
  type="flag"
  desc="Show this help message and exit"
  is_req=""
  is_vec=""
  __print_flag_line
  [[ -z "${__barg_opts[epilog_lines]}" || -n "${BARG_SUBCOMMAND}" ]] && return

  declare -n epilogs="${__barg_opts[epilog_lines]}"
  local epilog=''
  IFS=$'\n' epilog="${epilogs[*]}"
  barg::colorize epilog
  printf '\n%b\n' "${epilog}"
}

# barg::dynamic_completion <params[@]> <types[@]> <descs[@]> <extargs[@]>
function barg::dynamic_completion {
  # no need to continue if --help
  ${help_message_generation} && [ "${__barg_opts[help_enabled]}" == 'true' ] && return

  local -n params="${1}"
  local -n types="${2}"
  local -n descs="${3}"
  local -n flags="${4}"
  shift 4

  local curr=""
  local total_args="${#argv[@]}"
  ((total_args > 0)) && curr="${argv[-1]}"
  local __all_subcommands=("${!__barg_subcommands[@]}")
  if ((${#__all_subcommands[@]} > 0 && total_args == 1)); then
    compgen -V subcmds -W "${__all_subcommands[*]/#\*/}" -- "${curr}"

    for c in "${subcmds[@]}"; do
      printf '%s\t0\t%s\n' "${c}" "${__barg_subcommands["${c}"]:-${__barg_subcommands["*${c}"]}}"
    done

    [ "${__barg_opts[subcommand_required]}" == 'true' ] && {
      if [[ "${__barg_opts[help_enabled]}" == 'true' && "${curr}" == '-'* ]]; then
        local desc="Show this help message and exit"
        printf -- "--help\t1\t%-10s %s\n" "flag" "${desc}"
        printf -- "-h\t1\t%-10s %s\n" "flag" "${desc}"
      fi
      return
    }
  fi

  [[ "${#params[@]}" == 0 ]] && return
  local show_def_hint=false
  [[ "${__barg_opts[show_defaults]}" == 'true' ]] && show_def_hint=true

  local long_opts=()
  local short_opts=()
  function __print_flag_line {
    if [[ "${total_args}" != '0' && "${long}" != "${curr}"* ]]; then
      [[ -z "${short}" || "${short}" != "${curr}"* ]] && return
    fi

    [ -z "${type}" ] && type="enum"
    [ -n "${is_vec}" ] && type="[${type}]"
    local color=1
    [ -n "${is_req}" ] && color=2

    if ${show_def_hint} && [[ -n "${__defaults[i]}" && "${type}" != "switch" ]]; then
      local def_v="${__defaults[i]}"
      # For strings, limit to 45 chars and add if needed
      [[ "${type}" == "str" && ${#def_v} -gt 45 ]] && def_v="${def_v:0:44}…"
      desc="${desc} (def: \"${def_v}\")"
    fi

    [ "${type}" == "switch" ] && type="${name}"

    [[ -n "${long}" && "--" == "${curr:0:2}"* ]] && {
      printf -v a -- "%s\t%s\t%-10s %s\n" "${long}" "${color}" "${type}" "${desc}"
      long_opts+=("${a}")
    }
    [[ -n "${short}" && "${curr}" != --* ]] && {
      printf -v a -- "%s\t%s\t%-10s %s\n" "${short}" "${color}" "${type}" "${desc}"
      short_opts+=("${a}")
    }
  }

  local param="" short="" long="" \
    type="" desc="" is_req="" is_vec=""

  local count="${#params[@]}"
  local prev=""
  ((total_args > 1)) && prev="${argv[-2]}"
  for ((i = 0; i < count; i++)); do
    param="${params[i]}"
    type="${types[i]}"
    desc="${descs[i]}"
    ((${#flags[i]} == 2)) && is_req='!' && is_vec='s'
    [[ "${flags[i]}" == '!' ]] && is_req='!' || is_req=''
    [[ "${flags[i]}" == 's' ]] && is_vec='s' || is_vec=''

    short=""
    long=""
    if [[ "${param}" != *'}' ]]; then
      param="${param%%\ *}"
      if [[ "${param}" == ?'/'* ]]; then
        short="-${param%/*}"
        long="--${param#*/}"
      else
        (("${#param}" > 1)) && long="--${param}" || short="-${param}"
      fi

      if [[ -z "${type}" && -n "${prev}" ]] && [[ "${prev}" == "${short}" || "${prev}" == "${long}" ]]; then
        local maybe_checked_list="${params[i]#*\ }" # [...]
        local STR="${maybe_checked_list:1:-1}"
        while [[ "${STR}" =~ ${__lst_regex__} ]]; do
          local value="${BASH_REMATCH[2]:-${BASH_REMATCH[4]}}"
          [[ "${value}" == "${curr}"* ]] && printf '%s\t3\t%10s %s\n' "${value}" "enum" "value for ${prev}"
          STR="${STR/#"${BASH_REMATCH[0]}"/}"
        done
        exit
      fi

      for cur_arg in "${argv[@]:0:$((total_args - 1))}"; do
        [[ "${cur_arg}" == "${short}" || "${cur_arg}" == "${long}" ]] && continue 2
      done

      __print_flag_line
      continue
    fi

    param="${param:1:-1}"
    param="${param#*\{}"
    name="${type}"
    local lopt_count="${#long_opts[@]}"
    local sopt_count="${#short_opts[@]}"
    while [[ "${param}" =~ ${__obj_regex__} ]]; do
      type="switch"
      local short="${BASH_REMATCH[2]}"
      local long="${BASH_REMATCH[3]}"
      local value="${BASH_REMATCH[5]:-${BASH_REMATCH[7]}}"
      local desc="${BASH_REMATCH[12]:-${BASH_REMATCH[14]:-${desc}}}"

      if [ -n "${short}" ]; then
        short="-${short:0:-1}"
        long="--${long}"
      else
        (("${#long}" > 1)) && long="--${long}" || {
          short="-${long}"
          long=''
        }
      fi

      for cur_arg in "${argv[@]:0:$((total_args - 1))}"; do
        [[ "${cur_arg}" == "${short}" || "${cur_arg}" == "${long}" ]] && {
          long_opts=("${long_opts[@]:0:lopt_count}")
          short_opts=("${short_opts[@]:0:sopt_count}")
          break 2
        }
      done

      __print_flag_line
      param="${param/#"${BASH_REMATCH[0]}"/}"
    done
  done

  # in the main function, -h/--help was already found or not
  if ! ${help_message_generation} && [ "${__barg_opts[help_enabled]}" == 'true' ]; then
    param=""
    short="-h"
    long="--help"
    type="flag"
    desc="Show this help message and exit"
    is_req=""
    is_vec=""
    __print_flag_line
  fi

  printf '%s' "${long_opts[@]}" "${short_opts[@]}"
  return
}

# Parse command line arguments based on a
# special definition syntax
# Usage:
#   barg::parse "<command_line>" <<< "${definitions}"
# Example:
# This will have 2 subcommands, and will require
# spare arguments for `echo`
# will have flags (true/false)
# For `tell` will have required (note the `!`) parameters
# ```bash
#   barg::parse "${@}" <<EOF
#     #[always]
#     meta {
#       argv_zero: 'Example'
#       subcommand_required: true
#       spare_args_required: true
#       help_enabled: true
#       spare_args_var: 'THIS_POSITIONAL_ARGS'
#     }
#
#     commands {
#       tell: 'Send message to someone'
#       *echo: 'Print arguments'
#     }
#
#     @tell ! r/receiver :str => TELL_MESSAGE_RECEIVER
#     @tell ! m/message :str => TELL_MESSAGE
#
#     @echo n/no-lf :flag => ECHO_NO_LINEFEED
#     @ v/verbose :flag => MAIN_VERBOSE
#   EOF
# ```
function barg::parse {
  [ -p /dev/stdin ] || return 1
  read -rt 0.1 __line_0
  if [[ "${__line_0}" == '#[always]' ]]; then
    __line_0=''
  else
    ((${#} == 0)) && return 1
  fi

  # shellcheck disable=SC1003
  local __str_regex__='("((\\"|[^"])*?)"|'\''((\\'\''|[^'\''])*?)'\'')'
  local __val_regex__='("((\\"|[^"])*?)"|'\''((\\'\''|[^'\''])*?)'\''|(-?[0-9]+|true|false))'
  local __arg_pattern__='[A-Za-z!?@#_.:<>]?/?[A-Za-z0-9!?@#_.:<>\-]+'

  # Int or float
  local __num_regex__='^((-?[0-9]{1,3}(_[0-9]{3})*|-?[0-9]*)|(-?[0-9]{1,3}(_[0-9]{3})+\.([0-9]{3}(_[0-9]{1,3})*|[0-9]{1,3})|-?[0-9]+\.[0-9]+))$'
  local __int_regex__='^(-?[0-9]{1,3}(_[0-9]{3})*|-?[0-9]*)$'
  local __flt_regex__='^(-?[0-9]{1,3}(_[0-9]{3})+\.([0-9]{3}(_[0-9]{1,3})*|[0-9]{1,3})|-?[0-9]+\.[0-9]+)$'
  local __opt_regex__="meta \{((\s*([\*A-Za-z_][A-Za-z0-9_-]+)\s*:\s*${__val_regex__}\s*)+)\}"
  local __obi_regex__="\s*([\*A-Za-z_][A-Za-z0-9_-]+)\s*:\s*${__val_regex__}\s*"
  local __obj_regex__="\s*(([A-Za-z!?@#_.:<>]/)?([A-Za-z0-9!?@#_.:<>\-]+)\s*:\s*${__val_regex__})\s*(h${__str_regex__})?"
  local __lst_regex__="\s*${__val_regex__}\s*"
  local __def_regex__=(
    '\s*(@[a-zA-Z0-9\-_]*)?\s*(!)?\s*'
    "(${__arg_pattern__}\s+:(str|float|int|num|flag)(s)?"
    "|(\"((\\\\\"|[^\"])*?)\")?\s*\{(\s*${__arg_pattern__}\s*:\s*${__val_regex__}\s*(h\"((\\\"|[^\"])*?)\")?\s*)+\}"
    "|${__arg_pattern__}\s*\[(\s*\s*${__val_regex__}\s*)+\])"
    "\s*${__val_regex__}?\s*"
    '=>\s*([a-zA-Z][a-zA-Z0-9_]*)'
    "\s*${__val_regex__}?"
  )
  printf -v __def_regex__ '%s' "${__def_regex__[@]}"

  local __ilegal_var_names__=(
    BASH BASH_ENV BASH_SUBSHELL BASHPID BASH_VERSINFO BASH_VERSION CDPATH
    DIRSTACK EDITOR EUID FUNCNAME GLOBIGNORE GROUPS HOME HOSTNAME
    HOSTTYPE IFS IGNOREEOF LC_COLLATE LC_CTYPE LINENO MACHTYPE OLDPWD
    OSTYPE PATH PIPESTATUS PPID PROMPT_COMMAND PS1 PS2 PS3 PS4 PWD
    REPLY SECONDS SHELLOPTS SHLVL TMOUT UID
  )

  mapfile -t STDIN_LINES
  for line in "${__line_0}" "${STDIN_LINES[@]}"; do
    # if line.trim_left().starts_with("#") { continue; }
    [[ "${line#*"${line%%[![:space:]]*}"}" == '#'* ]] && continue
    STDIN_STR+="${line}"$'\n'
  done

  if [[ "${STDIN_STR}" =~ ${__opt_regex__} ]]; then
    local obj="${BASH_REMATCH[1]}"
    # Escapes in string must be escaped
    STDIN_STR="${STDIN_STR/"${BASH_REMATCH[0]//\\/\\\\}"/}"
    while [[ ${obj} =~ ${__obi_regex__} ]]; do
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[3]:-${BASH_REMATCH[5]:-${BASH_REMATCH[7]}}}"
      if [[ " ${!__barg_opts[*]} " != *" ${key} "* ]]; then
        barg::exit_msg "Invalid option" "Option {acc}${key}{r} does not exist"
      fi
      __barg_opts[${key}]="${val}"
      obj="${obj/#"${BASH_REMATCH[0]//\\/\\\\}"/}"
    done
    unset key val obj
  fi
  if [[ "${STDIN_STR}" =~ ${__opt_regex__/#meta/commands} ]]; then
    local obj="${BASH_REMATCH[1]}"
    # Escapes in string must be escaped
    STDIN_STR="${STDIN_STR/"${BASH_REMATCH[0]//\\/\\\\}"/}"
    while [[ ${obj} =~ ${__obi_regex__} ]]; do
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[3]:-${BASH_REMATCH[5]}}"
      __barg_subcommands[${key}]="${val}"
      obj="${obj/#"${BASH_REMATCH[0]//\\/\\\\}"/}"
    done
    unset key val obj
  fi

  local palette="${__barg_opts[color_palette]:-${BARG_COLOR_PALETTE}}"
  [ -n "${palette}" ] && {
    mapfile -t palette <<<"${palette//:/$'\n'}"
    __barg_palette[acc]="\x1b[${palette[0]:-0}m"
    __barg_palette[cmd]="\x1b[${palette[1]:-0}m"
    __barg_palette[req]="\x1b[${palette[2]:-0}m"
    __barg_palette[err]="\x1b[${palette[3]:-0}m"
    __barg_palette[str]="\x1b[${palette[4]:-0}m"
    __barg_palette[any]="\x1b[${palette[5]:-0}m"
  }
  unset palette

  local help_or_completion=false
  local completion_mode=''
  if [ "${__barg_opts[completion_enabled]}" == 'true' ]; then
    if [[ "${1}" == '@nucomp' || "${1}" == '@tsvcomp' ]]; then
      help_or_completion=true
      completion_mode="${1}"
      shift 2 # shift @nucomp and progname
    fi
  fi

  declare -g BARG_SUBCOMMAND=""
  local BARG_SUBCOMMAND_NEEDS_SPARE=false
  # Try to get the possible sub command
  if [ "${1}" == '--' ]; then
    [ -z "${completion_mode}" ] && shift 1
  elif [ -n "${__barg_subcommands[*]}" ]; then
    # shellcheck disable=SC2206
    local __all_subcommands=("${!__barg_subcommands[@]}")
    if barg::is_in_arr "${1}" "${__all_subcommands[@]/#\*/}"; then
      # check if it does not need extras
      [[ " ${__all_subcommands[*]} " == *" *${1} "* ]] && {
        BARG_SUBCOMMAND_NEEDS_SPARE=true
      }
      BARG_SUBCOMMAND="${1}"
      [ -z "${completion_mode}" ] && shift 1
    fi
  fi
  local __missing_subcmd=false
  if [ "${__barg_opts[subcommand_required]}" == "true" ] && [ -n "${__barg_subcommands[*]}" ] && [ -z "${BARG_SUBCOMMAND}" ]; then
    __missing_subcmd=true
  fi

  local argv=("${@}")
  barg::normalize_args # Normalize joint arguments, from '-abc' to '-a -b -c'

  local help_message_generation=false
  if [ "${__barg_opts[help_enabled]}" == 'true' ]; then
    local i=0
    while ((i <= ${#argv[@]})); do
      if [[ "${argv[i]}" == '--' ]]; then
        ((i++))
      elif [[ "${argv[i]}" == '-h' || "${argv[i]}" == '--help' ]]; then
        help_or_completion=true
        help_message_generation=true
        break
      fi
      ((i++))
    done
  fi

  if ! ${help_or_completion} && ${__missing_subcmd}; then
    # shellcheck disable=SC2206
    local __all_subcommands=("${!__barg_subcommands[@]}")
    local lines=()
    for sub in "${__all_subcommands[@]}"; do
      lines+=("${sub#\*}" "${__barg_subcommands["${sub}"]}")
    done
    printf -v plines "  - {acc}%-16s{r} %s\n" "${lines[@]}"
    barg::exit_msg "Missing subcommand" "A subcommand is required, one of:\n${plines:0:-1}"
  fi

  local -a __signatures=()
  local -a __types=()
  local -a __flags=()
  local -a __variables=()
  local -a __defaults=()
  local -a __descriptions=()
  local __last_valid_param_def=""
  while [[ "${STDIN_STR}" =~ ${__def_regex__} ]]; do
    STDIN_STR="${STDIN_STR/#"${BASH_REMATCH[0]}"/}"

    if [ "${BASH_REMATCH[0]}" == "${__last_valid_param_def}" ]; then
      barg::exit_msg "Invalid directive" "Not able to continue, error before: \n${__last_valid_param_def}"
    fi
    __last_valid_param_def="${BASH_REMATCH[0]}"

    # for i in "${!BASH_REMATCH[@]}"; do printf '%d = %q\n' "${i}" "${BASH_REMATCH[i]}"; done
    local flag_scope="${BASH_REMATCH[1]}" # ?-> Arg subcommand

    # If it's only `@`, the param is for the use without subcommand
    [[ -n "${BARG_SUBCOMMAND}" && "${flag_scope}" == '@' ]] && continue
    [[ -n "${flag_scope:1}" && "${flag_scope:1}" != "${BARG_SUBCOMMAND}" ]] && continue

    local param_is_req="${BASH_REMATCH[2]}"                                               # ?-> Is required
    local param_pattern="${BASH_REMATCH[3]}"                                              # !-> Pattern
    local param_type="${BASH_REMATCH[4]}"                                                 # ?-> Data type
    local param_is_vec="${BASH_REMATCH[5]}"                                               # ?-> is a vec
    local param_switch="${BASH_REMATCH[7]}"                                               # ?-> Switch name
    local param_def_value="${BASH_REMATCH[27]:-${BASH_REMATCH[29]:-${BASH_REMATCH[31]}}}" # ?-> Default value
    local param_var_name="${BASH_REMATCH[32]}"                                            # !-> Variable name
    local param_help_desc="${BASH_REMATCH[34]:-${BASH_REMATCH[36]}}"                      # ?-> Def description

    barg::is_in_arr "${param_var_name}" "${__ilegal_var_names__[@]}" && barg::exit_msg "Ilegal variable name" "{acc}${param_var_name}{r} is a reserved variable name."

    __signatures+=("${param_pattern}")
    __types+=("${param_type:-${param_switch}}")
    __variables+=("${param_var_name}")
    __defaults+=("${param_def_value}")
    __flags+=("${param_is_req}${param_is_vec}")
    ${help_or_completion} && __descriptions+=("${param_help_desc}")
  done

  # String that is non-zero lenght after being striped
  # should mean that regex was not able to match...
  # because it's not available and not because the user made some mistakes
  if [ -n "${STDIN_STR}" ]; then
    STDIN_STR="${STDIN_STR//$'\n'/}"
    STDIN_STR="${STDIN_STR//\ /}"
    if [ -n "${STDIN_STR}" ]; then
      barg::exit_msg "Regex error" "LIBC regex support: GLIBC required"
    fi
  fi

  case "${completion_mode}" in
  '@nucomp')
    barg::dynamic_completion \
      "__signatures" "__types" "__descriptions" "__flags" "${argv[@]}" |
      barg::nucompletion_adapter
    exit
    ;;
  '@tsvcomp')
    barg::dynamic_completion \
      "__signatures" "__types" "__descriptions" "__flags" "${argv[@]}"
    exit
    ;;
  esac

  if ${help_message_generation}; then
    barg::gen_help_message \
      "__signatures" "__types" "__descriptions" "__flags"
    exit
  fi

  declare -a BARG_TAKEN_ARGS
  declare -Ag BARG_ARGV_TABLE

  local i=0
  local _last_argv=''
  while ((i < ${#argv[@]})); do
    # skip what is not meant to be flags
    # -- -some other
    # ++ ++++ ^
    [[ "${argv[i]}" == '--' ]] && {
      ((i = i + 2))
      continue
    }
    # skip what does not look like flag
    # maybe --this
    # +++++ ^
    [[ "${argv[i]}" != -* ]] && {
      ((i++))
      continue
    }

    # push flag, and where a possible value is
    # not skipping value since flag may not use it
    _last_argv="${argv[i]}"
    ((i++))

    # always append, since a leading space does not
    # make any changes, but the [ -z "${...}" ] does
    BARG_ARGV_TABLE["${_last_argv}"]+=" ${i}"
  done

  # in case of finding a flag at the end, and it expects a value, which is missing
  # if ((${#argv[@]} > 0)) && [[ "${argv[-1]}" == '-'* ]] && [ -n "${_last_argv}" ]; then
  #   local _maybe_flag="${_last_argv#*"${_last_argv%%[!-]*}"}"
  #   ((${#_maybe_flag} == 1)) && _maybe_flag+="/"
  #
  #   for i in "${!__signatures[@]}"; do
  #     echo [[ "${__signatures[i]}" == *"${_maybe_flag}"* ]]
  #     [[ "${__signatures[i]}" == *"${_maybe_flag}"* ]] && {
  #       [[ -n "${__types[i]}" && "${__types[i]}" != 'flag' ]] && {
  #         barg::exit_msg "Missing value" "Expected value for {acc}${_last_argv}{r} is not in command line"
  #       }
  #       break
  #     }
  #   done
  # fi
  # unset i _last_argv _maybe_flag

  local count="${#__variables[@]}"
  for ((i = 0; i < count; i++)); do
    barg::param_set "${__signatures[i]}" "${__variables[i]}" "${__defaults[i]}" "${__types[i]}" "${__flags[i]}"
  done

  local extras_count=0
  local extras_var_name="${__barg_opts[spare_args_var]:-BARG_SPARE_ARGS}"
  local i=0
  declare -ag "${extras_var_name}"
  for ((i = 0; i < ${#argv[@]}; i++)); do
    # options and flags are taken, so skip them
    [[ " ${BARG_TAKEN_ARGS[*]} " == *"${i}"* ]] && continue

    local arg="${argv[i]}"
    if [[ "${arg}" == '--' ]]; then
      ((i++))
      arg="${argv[i]}"
    elif [[ "${arg}" == -* ]]; then
      barg::exit_msg "Unknown flag" "Flag {acc}${arg}{r} is not recognized"
    fi

    declare -ag "${extras_var_name}+=(\"${arg//\"/\\\"}\")"
    ((extras_count++))
  done
  unset BARG_TAKEN_ARGS

  # shellcheck disable=SC2034
  declare -g "${extras_var_name}_COUNT"="${extras_count}"

  if ((extras_count < 1)); then
    if [[ -z "${BARG_SUBCOMMAND}" && "${__barg_opts[spare_args_required]}" == 'true' ]]; then
      barg::exit_msg "Missing arguments" "spare arguments are required"
    elif [[ -n "${BARG_SUBCOMMAND}" && "${BARG_SUBCOMMAND_NEEDS_SPARE}" == 'true' ]]; then
      barg::exit_msg "Missing arguments" "subcommand {acc}${BARG_SUBCOMMAND}{r} requires spare arguments"
    fi
  fi
  return 0
}
