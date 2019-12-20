#!/usr/bin/env bash
## High-level spelling check for notebooks (and Markdown and txt).
## Requires aspell and nbconvert.
##
## Display help and command-line options:
##   $ spelltest -h
##
## Count misspellings in text cells:
##   $ spelltest notebook.ipynb [...]
##
## Count misspellings in text cells including code tags:
##   $ spelltest -c notebook.ipynb [...]
##
## Count misspellings in text cells including code tags AND code cells:
##   $ spelltest -c -C notebook.ipynb [...]
##
## Dump notebook text (without code cells) and save to clipoard (OSX):
##   $ spelltest -p notebook.ipynb | pbcopy
##
set -e

usage() {
  echo "Usage: $(basename $0) notebook.ipynb"
  echo "  High-level spelling check for notebooks (and Markdown and txt)."
  echo "Options:"
  echo "  -c  Check <code> and <pre> tags within text cell"
  echo "  -C  Include code blocks"
  echo "  -p  Print Markdown to stdout"
  echo "  -h  Print this help and exit"
}

LOG_NAME="[$(basename $0 '.sh')]"
SRC_ROOT="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
WORDLIST="${SRC_ROOT}/wordlist.txt"

## Parse options

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

while getopts "cCph" opt; do
  case $opt in
    c) OPT_CHECK_CODE_TAGS=1;;
    C) OPT_INCLUDE_CODE_CELLS=1;;
    p) OPT_PRINT_STDOUT_ONLY=1;;
    h | *)
      usage
      exit 0
      ;;
  esac
done

# Args after flags
shift $((OPTIND - 1))


## Check requirmeents: aspell and nbconvert

if [[ ! -x "$(which aspell)" ]]; then
  echo "${LOG_NAME} Error: Requires the 'aspell' command" >&2
  exit 1
fi

if [[ -n "$(which jupyter-nbconvert)" ]]; then
  NBCONVERT_BIN="$(which jupyter-nbconvert)"
elif [[ -n "$(which nbconvert)" ]]; then
  NBCONVERT_BIN="$(which nbconvert)"
else
  echo "${LOG_NAME} Error: Requires the 'jupyter-nbconvert' command" >&2
  exit 1
fi


# Read file contents to string.
# Use Markdown if dumping to stdout. Use HTML for aspell check.
read_file_contents() {
  local fp="$1"
  local opts
  local contents

  if [[ "${fp: -4}" == ".txt" ]]; then
    contents="$(cat $fp)"

  elif [[ "${fp: -3}" == ".md" ]];  then
    echo "${LOG_NAME} TODO: Test Markdown ${fp}" >&2
    contents="$(cat $fp)"

  elif [[ "${fp: -6}" == ".ipynb" ]]; then
    # Use Markdown for stdout dump, html for aspell
    if [[ -n "$OPT_PRINT_STDOUT_ONLY" ]]; then
      opts+="--to=markdown"
    else
      opts+="--to=html"
    fi

    if [[ -z "$OPT_INCLUDE_CODE_CELLS" ]]; then
      # template removes input code cells
      if [[ -n "$OPT_PRINT_STDOUT_ONLY" ]]; then
        opts+=" --template=${SRC_ROOT}/tmpl/md.tpl"
      else
        opts+=" --template=${SRC_ROOT}/tmpl/html.tpl"
      fi
    fi

    contents="$($NBCONVERT_BIN $opts --stdout $fp 2>/dev/null)"

  else
    echo "${LOG_NAME} Error: File format not supported: ${fp}" >&2
    exit 1
  fi

  echo "$contents"
}

# Aspell < 0.60.8 requires a compiled dictionary
if [[ -z "$OPT_PRINT_STDOUT_ONLY" ]]; then
  # Only want to compile new dictionary if the wordlist has changed
  # Clean up extras at end of file
  checksum=$(crc32 "$WORDLIST")
  WORDDICT="/tmp/$(basename $0 '.sh')-${checksum}.rws"

  if [[ ! -f "$WORDDICT" ]]; then
    echo "${LOG_NAME} Compiling dictionary: ${WORDDICT}" >&2
    aspell --lang=en --encoding=utf-8 create master "$WORDDICT" < "$WORDLIST"
  else
    echo "${LOG_NAME} Using pre-compiled dictionary: ${WORDDICT}" >&2
  fi
fi


## Main

for fp in "$@"; do
  if [[ ! -f "$fp" ]]; then
    echo "${LOG_NAME} Error: File doesn't exist: ${fp}" >&2
    exit 1
  fi

  echo "File: $fp" >&2

  contents="$(read_file_contents $fp)"
  # Strip extras
  contents=$(echo "$contents" \
    | sed -e '/^<table class="tfo-notebook-buttons" align="left">/,/<\/table>/d')

  if [[ -n "$OPT_PRINT_STDOUT_ONLY" ]]; then
    # No spell check, just print file contents and move on
    echo "$contents"
    continue

  else
    aspell_opts="--lang=en_US --encoding=utf-8"

    if [[ -z "$OPT_CHECK_CODE_TAGS" ]]; then
      aspell_opts+=" --add-html-skip=code --add-html-skip=pre"
    fi

    echo "$contents" \
      | aspell list $aspell_opts --mode=html --add-extra-dicts="$WORDDICT" \
      | sort \
      | uniq -c
  fi
done


# Cleanup old aspell dicts
if [[ -f "$WORDDICT" ]]; then
  find /tmp -maxdepth 1 -type f \
       -name "$(basename $0 '.sh')*" ! -wholename "$WORDDICT" \
       -delete
fi
