#!/usr/bin/env bats
# Specs for sci-ml/strata/files/strata-hugepages, the ExecStartPre= and
# ExecStopPost= helper that grows and shrinks the 2 MiB hugetlb pool for
# one strata@<tag> instance.  The pool file and run dir are fakes under
# BATS_TEST_TMPDIR; a FIFO stands in for the kernel when a test needs it
# to grant fewer pages than asked for.

setup() {
	HELPER="${BATS_TEST_DIRNAME}/../../sci-ml/strata/files/strata-hugepages"
	export STRATA_HUGEPAGES_POOL="${BATS_TEST_TMPDIR}/nr_hugepages"
	export STRATA_HUGEPAGES_RUNDIR="${BATS_TEST_TMPDIR}/run"
	echo 0 > "$STRATA_HUGEPAGES_POOL"
}

_helper() {
	sh "$HELPER" "$@"
}

_pool() {
	cat "$STRATA_HUGEPAGES_POOL"
}

# A kernel that holds HAVE pages and grants at most CAP: it answers the
# helper's read, takes its write, then answers the read-back.  Any
# rollback write lands in ROLLBACK_FILE.  Each FIFO open blocks until
# the helper opens the other end, so `timeout` keeps a helper that never
# does from hanging the suite.
_stingy_kernel() {
	rm -f "$STRATA_HUGEPAGES_POOL"
	mkfifo "$STRATA_HUGEPAGES_POOL"
	ROLLBACK_FILE="${BATS_TEST_TMPDIR}/rollback"
	# shellcheck disable=SC2016 # expanded by the inner sh
	timeout 5 sh -c '
		echo "$2" > "$1"
		read -r _want < "$1"
		echo "$3" > "$1"
		cat "$1" > "$4"
	' _ "$STRATA_HUGEPAGES_POOL" "$1" "$2" "$ROLLBACK_FILE" 3>&- &
}

@test 'reserve grows the pool by the requested pages' {
	echo 10 > "$STRATA_HUGEPAGES_POOL"

	run _helper reserve mytag 512

	[ "$status" -eq 0 ]
	[ "$(_pool)" -eq 522 ]
}

@test 'release gives back exactly what that instance reserved' {
	_helper reserve a 100
	_helper reserve b 50

	run _helper release a

	[ "$status" -eq 0 ]
	[ "$(_pool)" -eq 50 ]
}

@test 'release without a reservation is a quiet no-op' {
	echo 7 > "$STRATA_HUGEPAGES_POOL"

	run _helper release never-started

	[ "$status" -eq 0 ]
	[ "$(_pool)" -eq 7 ]
	[ -z "$output" ]
}

@test 'release never takes the pool below zero' {
	_helper reserve a 100
	echo 30 > "$STRATA_HUGEPAGES_POOL"

	run _helper release a

	[ "$status" -eq 0 ]
	[ "$(_pool)" -eq 0 ]
}

@test 'a second reserve for one tag replaces the stale reservation' {
	_helper reserve a 100

	run _helper reserve a 40

	[ "$status" -eq 0 ]
	[ "$(_pool)" -eq 40 ]
	_helper release a
	[ "$(_pool)" -eq 0 ]
}

@test 'a short grant is rolled back and the service still starts' {
	_stingy_kernel 10 300

	run _helper reserve mytag 512
	wait

	[ "$status" -eq 0 ]
	[ "$(cat "$ROLLBACK_FILE")" -eq 10 ]
	[[ "$output" == *'got 290 of 512'* ]]
	[ ! -e "${STRATA_HUGEPAGES_RUNDIR}/mytag" ]
}

@test 'reserve rejects a page count that is not a positive integer' {
	for _bad in '' 0 -5 12x ' 7'; do
		run _helper reserve mytag "$_bad"
		[ "$status" -eq 1 ]
		[[ "$output" == *'positive integer'* ]]
	done
	[ "$(_pool)" -eq 0 ]
}

@test 'a tag that could escape the run dir is rejected' {
	for _bad in '' '../x' 'a/b' '.' '..'; do
		run _helper release "$_bad"
		[ "$status" -eq 1 ]
		[[ "$output" == *'instance tag'* ]]
	done
}

@test 'unknown commands print usage and fail' {
	run _helper grow mytag 1

	[ "$status" -eq 1 ]
	[[ "$output" == *'Usage:'* ]]
}

@test 'a pool it cannot write is a warning, not a failed start' {
	chmod 0444 "$STRATA_HUGEPAGES_POOL"

	run _helper reserve mytag 8

	[ "$status" -eq 0 ]
	[[ "$output" == *'cannot set'* ]]
	[ "$(_pool)" -eq 0 ]
	[ ! -e "${STRATA_HUGEPAGES_RUNDIR}/mytag" ]
}
