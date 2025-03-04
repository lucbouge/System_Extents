#!/usr/bin/env bash 

# trap 'eval rm -f ${T}? /tmp/golden*$$ /tmp/output$$ /tmp/err$$ /tmp/opts$$ /tmp/pairs$$ $TESTS ${T}-self-?-?.dat' 0
trap exit 2 15

# put the files with shared extents here-- must be in a filesystem that supports reflinks
TEST_DIR=${TEST_DIR:-/mnt/img}
T=$TEST_DIR/testfile$$.

TESTS=/tmp/cmds$$

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

# clone it a few times
copy "${T}0" "${T}1" # same
copy "${T}0" "${T}2" ; echo foo | dd "of=${T}2" bs=1 seek=409600 conv=notrunc 2>/dev/null   # one change
copy "${T}2" "${T}3" ; echo bar | dd "of=${T}3" bs=1 seek=942080 conv=notrunc 2>/dev/null   # two changes from ${T}0
copy "${T}0" "${T}4" ; echo -n foo >> "${T}4"  # longer
copy "${T}0" "${T}5" ; echo -n bar >> "${T}5"  # longer but different
copy "${T}0" "${T}6" ; echo -n barf >> "${T}6" # longest

sync # needed to ensure data are stable in allocated file extents

# compare and check output against cmp

# opts:
cat <<xxx >/tmp/opts$$

-b
-l
-s
-bl
xxx

cat <<xxx >/tmp/pairs$$
${T}0 ${T}1
${T}0 ${T}2
${T}0 ${T}3
${T}3 ${T}4
${T}4 ${T}5
${T}5 ${T}6
xxx

while read opts
do
    while read f g
    do 
	      echo "$opts $f $g"
    done </tmp/pairs$$
done </tmp/opts$$ >$TESTS

cat >>"$TESTS" <<xxx
-bl -i 409600:1048576 ${T}2 ${T}4
-bl -i 409600:1048576 ${T}3 ${T}5
-bl -i 409600:1048576 ${T}3 ${T}6
xxx

if [ "$(uname)" = Linux ]
then
    # extra tests for self-sharing files
    (cd "$TEST_DIR" || exit 1; ~-/mkself 1 1; mv self.dat "${T}-self-1-1.dat"; ~-/mkself 2 2; mv self.dat "${T}-self-2-2.dat")
    cat >>$TESTS <<-EOF
    -i 0:4096 ${T}-self-1-1.dat ${T}-self-1-1.dat
    -i 0:4096 -n 4096 ${T}-self-1-1.dat ${T}-self-1-1.dat
    -bl -i 0:4096 ${T}-self-1-1.dat ${T}-self-1-1.dat
    -bl -i 0:4096 -n 4096 ${T}-self-1-1.dat ${T}-self-1-1.dat
EOF
fi

FAILED=0
declare -a testargs

start() {
    echo -n "Comparing: ${testargs[*]}  : "
    GOOD=1
}
    
fail() {
    GOOD=0 FAILED=1
    echo "Failed : $1"
}

faildiff() {
    fail "$3"
    echo diff cmp vs ccmp ; diff -bB "$1" "$2"
    echo
}    

while read -a testargs
do
    start
    rm -f /tmp/golden$$ /tmp/golden-err$$ /tmp/output$$ /tmp/err$$
    /usr/bin/cmp "${testargs[@]}" >/tmp/golden$$ 2>/tmp/golden-err$$
    CMPEXIT=$?
    ./ccmp_original.sh "${testargs[@]}" >/tmp/output$$ 2>/tmp/err$$
    CCMPEXIT=$?
    if [ $CCMPEXIT -ne $CMPEXIT ]
    then fail "exit status differs ($CMPEXIT for cmp, $CCMPEXIT for ccmp)" 
    fi
    if ! cmp -s /tmp/golden$$ /tmp/output$$ 
    then faildiff /tmp/golden$$ /tmp/output$$ "stdout differs" 
    fi
    if ! cmp -s /tmp/golden-err$$ /tmp/err$$
    then faildiff /tmp/golden-err$$ /tmp/err$$ "stderr differs" 
    fi
    if [ $GOOD -eq 1 ]
    then echo Passed
    fi
done < "$TESTS"

exit $FAILED
