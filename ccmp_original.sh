#!/usr/bin/env bash

# Clone-aware cmp

if [ $(uname) = Darwin ]
then
  if [ ! -x /usr/local/opt/gnu-getopt/bin/getopt ]
  then echo "must install gnu getopt" ; exit 1
  fi
  PATH="/usr/local/opt/gnu-getopt/bin:$PATH" # use gnu getopt
fi

version() { echo ccmp v1.0 Aug 2021; }

help() {
    usage
    echo
    version
    echo
    cat <<\xxx
Acts like cmp(1), but uses "extents" (which must be in the same dir or on the $PATH)
to apply cmp only to blocks that are not shared between file1 and file2.
<opts> are the same as those for cmp.  -b -l -s are the only useful ones.
Setting a skip or limit will only result in incorrect output.

Author: Mario Wolczko mario@wolczko.com

See LICENSE file for licensing.
xxx
}

usage() { echo usage: "$0" '<cmp-opts> file1 file2' ; }

trap 'rm -f /tmp/cmpout$$ /tmp/cmperr$$' 0
trap exit 2 15

declare -a OrigArgs=("$*")
declare -a CMPOPTS
declare -a ExtArgs
AWK1="'"'{$5+='"'"'"$Start1"'"'"'; $5 = $5 ","; sub(/, line [0-9]*/,""); print}'"'" # for stdout
AWK2="'"'/EOF/ {$7+='"'"'"$Start1"'"'"'; $7 = $7 ","; sub(/, in line [0-9]*/,""); print; next}'"'" #stderr
ONE=1 # exit on first difference
BYTES=0
SKIP=0
VERBOSE=0
ARGS=$(getopt -n "$0" -l "help,ignore-initial:,print_bytes,verbose,bytes:,quiet,silent,version" -o "bhi:ln:sv" -- "$@")
if [ $? -ne 0 ]; then
    usage; exit;
fi

eval set -- "$ARGS"
while :
do
    case "$1" in
      -b|--print-bytes)
        BYTES=1  ONE=1
        CMPOPTS+=(-b)
        AWK1="'"'{$5+='"'"'"$Start1"'"'"'; printf "%s %s %s %s %s %s %3s %s %3s %s\n", $1, $2, $3, $4, $5, $8, $9, $10, $11, $12 }'"'"
	      #AWK2="'{print}'"
        shift;;
      -h|--help) help; exit 0;;
      -i|--ignore-initial)
	      SKIP=1
	      #CMPOPTS+=(-i "$2")
	      ExtArgs+=(-i "$2")
        AWK1="'"'{$1-='"'"'"$Start1"'"'"'; printf "%7s %3s %3s\n", $1, $2, $3}'"'"
	      shift 2;;
      -l|--verbose)
        VERBOSE=1 ONE=0
        CMPOPTS+=(-l)
        AWK1="'"'{$1+='"'"'"$Start1"'"'"'; printf "%7s %3s %3s\n", $1, $2, $3}'"'"
#      	AWK2="'"'/EOF/ {$7+='"'"'"$Start1"'"'"'; sub(/which is/,"after byte");print}'"'"
      	AWK2="'"'/EOF/ {$7+='"'"'"$Start1"'"'"'; print}'"'"
        shift;;
      -n|--bytes)
        #CMPOPTS+=(-n "$2")
        ExtArgs+=(-n "$2")
        shift 2;;
      -s|--quiet|silent) AWK1="'{}'"; AWK2="$AWK1"; shift;;
      -v|--version) version; exit;;
      --) shift; break;;
      *) echo 'arg parsing error'; exit 1;;
    esac
done

if (( BYTES && VERBOSE ))
then
    if (( ! SKIP ))
    then
	    AWK1="'"'{$1+='"'"'"$Start1"'"'"'; printf "%7s %3s %-4s %3s %s\n", $1, $2, $3, $4, $5}'"'"
#	    AWK2="'"'/EOF/ {$7+='"'"'"$Start1"'"'"'; sub(/which is/,"after byte"); print}'"'"
    	    AWK2="'"'/EOF/ {$7+='"'"'"$Start1"'"'"'; print}'"'"
    else
	    AWK1="'"'{printf "%s %3s %-4s %3s %s\n", $1, $2, $3, $4, $5}'"'"
#	    AWK2="'"'/EOF/ {sub(/which is/,"after byte"); print}'"'"
    	    AWK2="'"'/EOF/ {print}'"'"
    fi
    
fi

case $# in
    1) cmp "${OrigArgs[@]}" ; exit $? ;;
    2) A="$1" B="$2" ;;
    3) A="$1" B="$2" ExtArgs+=(-i "$3") ;;
    4) A="$1" B="$2" ExtArgs+=(-i "$3:$4") ;;
    *) usage ; exit ;;
esac

cmpAwkLoop() {
  declare -i Start1 Start2 Len Cmp
  declare -i Cmps=1 # logical AND of all the inverted cmp statuses (ie 1 if all returned 1 [ie same], 0 otherwise)
  while read Start1 Start2 Len
  do
      cmp "${CMPOPTS[@]}" -i "$Start1:$Start2" -n "$Len" "$A" "$B" >/tmp/cmpout$$ 2>/tmp/cmperr$$
      Cmp=$?
      eval awk "$AWK1" /tmp/cmpout$$
      eval awk "$AWK2" /tmp/cmperr$$ 1>&2
      (( Cmps = Cmps && ! Cmp )) # cmp returns 0 for same, 1 for different
      if (( ONE && Cmp ))
      then break
      fi
  done
  return "$Cmps"
}

#sync # extents can be fooled by write data in flight, so stabilize - use fsync in extents? XXX
PATH=$(dirname "$0")":$PATH"
(set -x; extents -c "${ExtArgs[@]}" "$A" "$B" )| cmpAwkLoop
declare -a SAVED_PS=("${PIPESTATUS[@]}")
Cmps=${SAVED_PS[1]}
if [ ${SAVED_PS[0]} -ne 0 ]
then # extents failed, fall back to cmp
    (set -x; cmp ${OrigArgs[@]}) ; Cmps=$?
else
    Cmps=$(( ! Cmps ))
fi
exit $Cmps
