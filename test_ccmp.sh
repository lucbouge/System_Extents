#!/usr/bin/env bash 

set -u 

# trap 'eval rm -rf ${TEST_DIR}' 0
# trap exit 2 15

# put the files with shared extents here-- must be in a filesystem that supports reflinks
TEST_DIR=${TEST_DIR:-${HOME}/tmp/CCMP}
SUFFIX="$$"
T="${TEST_DIR}/ccmp_test_file_${SUFFIX}_"

CMP='/usr/bin/cmp'
CCMP='./ccmp.sh'

if [[ ! -x "${TEST_DIR}" ]]
then
    mkdir -p "${TEST_DIR}"
fi

TEST_FILE="${TEST_DIR}/ccmp_test_${SUFFIX}"
OPT_FILE="${TEST_DIR}/ccmp_options_${SUFFIX}"
PAIR_FILE="${TEST_DIR}/ccmp_pairs_${SUFFIX}"
GOLDEN_OUT_FILE="${TEST_DIR}/ccmp_golden_out_${SUFFIX}"
GOLDEN_ERR_FILE="${TEST_DIR}/ccmp_golden_err_${SUFFIX}"
CCMP_OUT_FILE="${TEST_DIR}/ccmp_out_${SUFFIX}"
CCMP_ERR_FILE="${TEST_DIR}/ccmp_err_${SUFFIX}"

# make a file
dd if=/dev/random of="${T}0" count=2048 2>/dev/null

case $(uname) in
Linux)  CP="cp --reflink" ;;
Darwin) CP="cp -c" ;;
esac

copy() {
    $CP "$@" ||
	  { echo "$CP failed -- perhaps filesystem at $TEST_DIR does not support reflinks?"; exit 1; }
}

# Clone it a few times
copy "${T}0" "${T}1" # same
copy "${T}0" "${T}2" ; echo foo | dd "of=${T}2" bs=1 seek=409600 conv=notrunc 2>/dev/null   # one change
copy "${T}2" "${T}3" ; echo bar | dd "of=${T}3" bs=1 seek=942080 conv=notrunc 2>/dev/null   # two changes from ${T}0
copy "${T}0" "${T}4" ; echo -n foo >> "${T}4"  # longer
copy "${T}0" "${T}5" ; echo -n bar >> "${T}5"  # longer but different
copy "${T}0" "${T}6" ; echo -n barf >> "${T}6" # longest

sync # needed to ensure data are stable in allocated file extents

# compare and check output against cmp

declare -a CCMP_OPTIONS=('-b' '-l' '-s' '-bl')

declare -a CCMP_PAIRS=(
"${T}0:${T}1"
"${T}0:${T}2"
"${T}0:${T}3"
"${T}3:${T}4"
"${T}4:${T}5"
"${T}5:${T}6"
)

declare -a TEST_CASES=()

for OPTION in "${CCMP_OPTIONS[@]}"
do
    for PAIR in "${CCMP_PAIRS[@]}"
    do 
        FILES="${PAIR/:/ }"
	    TEST_CASES+=("$OPTION $FILES")
     
    done 
done
TEST_CASES+=(
"-bl -i 409600:1048576 ${T}2 ${T}4"
"-bl -i 409600:1048576 ${T}3 ${T}5"
"-bl -i 409600:1048576 ${T}3 ${T}6"
)


declare -i FAILED GOOD
FAILED=0
GOOD=1

start() {
    echo -n "Comparing: ${TEST_ARGS}"
    GOOD=1
}
    
fail() {
    GOOD=0 FAILED=1
    echo "Failed: $1"
}

faildiff() {
    fail "$3"
    echo Diff cmp vs ccmp ; diff "$1" "$2"
    echo
}    

for TEST_ARGS in "${TEST_CASES[@]}"
do
    : echo ${TEST_ARGS}
done

################################################################################
echo "${GOLDEN_OUT_FILE}" "${GOLDEN_ERR_FILE}" "${CCMP_OUT_FILE}" "${CCMP_ERR_FILE}"

for TEST_ARGS in "${TEST_CASES[@]}"
do
    printf "TEST_ARGS: %s\n" "$TEST_ARGS"
    rm -f "${GOLDEN_OUT_FILE}" "${GOLDEN_ERR_FILE}" "${CCMP_OUT_FILE}" "${CCMP_ERR_FILE}"
    
    ##
    ${CMP} $TEST_ARGS > "${GOLDEN_OUT_FILE}" 2> "${GOLDEN_ERR_FILE}"
    CMP_EXIT_STATUS=$?
    ##
    ${CCMP} $TEST_ARGS > "${CCMP_OUT_FILE}" 2> "${CCMP_ERR_FILE}"
    CCMP_EXIT_STATUS=$?
    ##
    if [[ ${CCMP_EXIT_STATUS} != ${CMP_EXIT_STATUS} ]]
    then fail "exit status differs (${CMP_EXIT_STATUS} for cmp, ${CCMP_EXIT_STATUS} for ccmp)" 
    fi
    ##
    if ! cmp -s "${GOLDEN_OUT_FILE}"  "${CCMP_OUT_FILE}"
    then : faildiff "${GOLDEN_OUT_FILE}" "${CCMP_OUT_FILE}" "stdout differs" 
    fi
    if ! cmp -s "${GOLDEN_ERR_FILE}" "${CCMP_ERR_FILE}"
    then : faildiff "${GOLDEN_ERR_FILE}" "${CCMP_ERR_FILE}" "stderr differs" 
    fi
    if [[ $GOOD -eq 1 ]]
    then echo Passed
    fi
done

exit $FAILED
