#!/usr/bin/env /bin/bash
set -u

# Clone-aware cmp

GETOPT_PATH='/usr/local/opt/gnu-getopt/bin/getopt'

if [[ "$(uname)" = Darwin ]]
then
  if [[ ! -x "${GETOPT_PATH}" ]]
  then 
    echo "Must install GNU getopt at ${GETOPT_PATH}"
    exit 1
  fi
  export PATH="$(dirname "GETOPT_PATH"):$PATH" # use GNU getopt
fi

################################################################################

function version() { 
  echo ccmp v1.0 Aug 2021
}

function help() {
    usage
    echo
    version
    echo
    echo '
Acts like cmp(1), but uses "extents" (which must be in the same dir or on the \$PATH)
to apply cmp only to blocks that are not shared between file1 and file2.
<opts> are the same as those for cmp.  -b -l -s are the only useful ones.
Setting a skip or limit will only result in incorrect output.

Author: Mario Wolczko mario@wolczko.com

See LICENSE file for licensing.
'
}

function usage() { 
  echo usage: "$0 <cmp-opts> file1 file2" 
}

################################################################################

export REGULAR_CMP='/usr/bin/cmp'

OUT_FILE="/tmp/cmpout$$"
ERR_FILE="/tmp/cmperr$$"

trap 'rm -rf ${OUT_FILE} ${ERR_FILE}' 0
trap exit 2 15

declare -a ORIGINAL_ARGS=()
declare -a CMP_OPTIONS=()
declare -a EXTRA_ARGS=()
declare -a EXTENTS_ARGS=()


AWK1_="'"'{$5+='"'"'"$START1"'"'"'; $5 = $5 ","; sub(/, line [0-9]*/,""); print}'"'" # for stdout
AWK2="'"'/EOF/ {$7+='"'"'"$START1"'"'"'; $7 = $7 ","; sub(/, in line [0-9]*/,""); print; next}'"'" #stderr

declare -i EXIT_ON_FIRST_DIFFERENCE=1 # exit on first difference
declare -i BYTES=0
declare -i SKIP=0
declare -i VERBOSE=0
declare -i GLOBAL_CCMP_STATUS=0

declare AWK1=""
declare AWK2=""

ORIGINAL_ARGS=("$@")
PROGRAM_NAME="$0"

ARGS=$(\
  getopt -n "${PROGRAM_NAME}" \
  -l "help,ignore-initial:,print_bytes,verbose,bytes:,quiet,silent,version" \
  -o "bhi:ln:sv" \
  -- "$@" \
  )

echo $ARGS

if [ $? -ne 0 ]
then
    usage
    exit
fi

eval set -- "$ARGS"

while ((1))
do
    case "$1" in
      ##
      '-b'|'--print-bytes')
        BYTES=1 
        ONE=1
        CMP_OPTIONS+=('-b')
        AWK1="'"'{$5+='"'"'"$START1"'"'"'; printf "%s %s %s %s %s %s %3s %s %3s %s\n", $1, $2, $3, $4, $5, $8, $9, $10, $11, $12 }'"'"
	      #AWK2="'{print}'"
        shift;;
      ##
      '-h'|'--help') 
        help
        exit 0;;
      ##
      '-i'|'--ignore-initial')
	      SKIP=1
	      EXTRA_ARGS+=('-i' "$2")
        AWK1="'"'{$1-='"'"'"$START1"'"'"'; printf "%7s %3s %3s\n", $1, $2, $3}'"'"
	      shift 2;;
      ##
      '-l'|'--verbose')
        VERBOSE=1 
        STOP_AT_FIRST_ERROR=0
        CMP_OPTIONS+=('-l')
        AWK1="'"'{$1+='"'"'"$START1"'"'"'; printf "%7s %3s %3s\n", $1, $2, $3}'"'"
#      	AWK2="'"'/EOF/ {$7+='"'"'"$START1"'"'"'; sub(/which is/,"after byte");print}'"'"
      	AWK2="'"'/EOF/ {$7+='"'"'"$START1"'"'"'; print}'"'"
        shift;;
      ##
      '-n'|'--bytes')
        #CMPOPTS+=(-n "$2")
        EXTRA_ARGS+=('-n' "$2")
        shift 2;;
      ##
      '-s'|'--quiet'|'--silent') 
        AWK1='{}'
        AWK2='{}'
        shift;;
      ##
      '-v'|'--version') 
        version
        exit;;
      ##
      '--') 
        shift; 
        break;;
      ##
      *) 
        echo 'arg parsing error'
        exit 1;;
    esac
done

################################################################################

if (( BYTES && VERBOSE ))
then
    if (( ! SKIP ))
    then
	    AWK1="'"'{$1+='"'"'"$START1"'"'"'; printf "%7s %3s %-4s %3s %s\n", $1, $2, $3, $4, $5}'"'"
#	    AWK2="'"'/EOF/ {$7+='"'"'"$START1"'"'"'; sub(/which is/,"after byte"); print}'"'"
    	    AWK2="'"'/EOF/ {$7+='"'"'"$START1"'"'"'; print}'"'"
    else
	    AWK1="'"'{printf "%s %3s %-4s %3s %s\n", $1, $2, $3, $4, $5}'"'"
#	    AWK2="'"'/EOF/ {sub(/which is/,"after byte"); print}'"'"
    	    AWK2="'"'/EOF/ {print}'"'"
    fi
fi

################################################################################

case $# in
    1) 
      ${CCMP} "${ORIGINAL_ARGS[@]}"
      exit $?
      ;;
    ##
    2) 
      A="$1"
      B="$2"
      ;;
    ##
    3) 
      A="$1"
      B="$2" 
      EXTRA_ARGS+=('-i' "$3")
      ;;
    ##
    4) 
      A="$1" 
      B="$2" 
      EXTRA_ARGS+=('-i' "$3:$4") 
      ;;
    ##
    *) 
      usage
      exit 
      ;;
esac


################################################################################

function CCMP_AWK_LOOP {
  declare -i START1 START2 LENGTH CCMP
  CCMP=
  # GLOBAL_CCMP_STATUS is the logical AND of all the inverted cmp statuses 
  # (ie 1 if all returned 1, 0 otherwise)
  declare -i GLOBAL_CCMP_STATUS=1
  ##
  while read START1 START2 LENGTH
  do
      ${CCMP} -i "$START1:$START2" -n "$LENGTH" "$A" "$B" >${OUT_FILE} 2>${ERR_FILE}
      CCMP_RETURN_VALUE=$?
      ##
      eval awk "$AWK1" "${OUT_FILE}"
      eval awk "$AWK2" "${ERR_FILE}" 1>&2
      ##
      # CCMP returns 0 for same, 1 for different
      (( GLOBAL_CCMP_STATUS= GLOBAL_CCMP_STATUS && ! CCMP_RETURN_VALUE )) 
      if (( EXIT_ON_FIRST_DIFFERENCE && CCMP_RETURN_VALUE ))
      then 
        break
      fi
  done
  return ${GLOBAL_CCMP_STATUS}
}

################################################################################

## extents can be fooled by write data in flight, so stabilize - use fsync in extents?
# sync

CCMP_DIR="$(dirname "$0")"
PATH="${CCMP_DIR}:$PATH"

if [[ "${#EXTRA_ARGS}" = 0 ]]
then
  EXTENTS_ARGS=("$A" "$B")
else
  EXTENTS_ARGS=${EXTRA_ARGS}
  EXTENTS_ARGS+=("$A" "$B")
fi

(set -x; extents -c "${EXTENTS_ARGS[@]}") | CCMP_AWK_LOOP

declare -a PIPE_STATUS=("${PIPESTATUS[@]}")
CCMP_AWK_LOOP_EXIT_STATUS=${PIPE_STATUS[1]}
EXTENTS_EXIT_STATUS=${PIPE_STATUS[0]}


if (( EXTENTS_EXIT_STATUS != 0 ))
then # extents failed, fall back to regular cmp
    ${REGULAR_CMP} ${ORIGINAL_ARGS[@]}
    GLOBAL_CCMP_STATUS=$?
else
    (( GLOBAL_CCMP_STATUS = ! GLOBAL_CCMP_STATUS ))
fi
exit ${GLOBAL_CCMP_STATUS}
