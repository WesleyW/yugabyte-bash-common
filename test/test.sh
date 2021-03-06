#!/usr/bin/env bash

set -euo pipefail
cd "${BASH_SOURCE%/*}"
. ../src/yugabyte-bash-common.sh

declare -i num_assertions_succeeded=0
declare -i num_assertions_failed=0

declare -i num_assertions_succeeded_in_current_test=0
declare -i num_assertions_failed_in_current_test=0

cleanup() {
  local exit_code=$?
  if [[ -d $TEST_TMPDIR && $TEST_TMPDIR == /tmp/* ]]; then
    ( set -x; rm -rf "$TEST_TMPDIR" )
  fi
  exit "$exit_code"
}

increment_successful_assertions() {
  let num_assertions_succeeded+=1
  let num_assertions_succeeded_in_current_test+=1
}

increment_failed_assertions() {
  let num_assertions_failed+=1
  let num_assertions_failed_in_current_test+=1
}

assert_equals() {
  # Not using "expect_num_args", "log", "fatal", etc. in these assertion functions, because
  # those functions themselves need to be tested.
  if [[ $# -ne 2 ]]; then
    echo "assert_equals expects two arguments, got $#: $*" >&2
    exit 1
  fi
  local expected=$1
  local actual=$2
  if [[ $expected == $actual ]]; then
    increment_successful_assertions
  else
    echo "Assertion failed: expected '$expected', got '$actual'" >&2
    increment_failed_assertions
  fi
}

assert_failure() {
  if "$@"; then
    log "Command succeeded -- NOT EXPECTED: $*"
    increment_failed_assertions
  else
    log "Command failed as expected: $*"
    increment_successful_assertions
  fi
}

yb_test_logging() {
  assert_equals "$( log "Foo bar" 2>&1 | sed 's/.*\] //g' )" "Foo bar"
}

yb_test_sed_i() {
  local file_path=$TEST_TMPDIR/sed_i_test.txt
  cat >"$file_path" <<EOT
Hello world hello world
Hello world hello world
EOT
  sed_i 's/lo wo/lo database wo/g' "$file_path"
  local expected_result
  expected_result=\
'Hello database world hello database world
Hello database world hello database world'
  assert_equals "$expected_result" "$( <"$file_path" )"
}

yb_test_sha256sum() {
  local file_path=$TEST_TMPDIR/myfile.txt
  echo "Data data data" >"$file_path"
  local computed_sha256sum
  compute_sha256sum "$file_path"
  local expected_sha256sum="cda1ee400a07d94301112707836aafaaa1760359e3cb80c9754299b82586d4ec"
  assert_equals "$expected_sha256sum" "$computed_sha256sum"
  local checksum_file_path=$file_path.sha256
  echo "$expected_sha256sum" >"$checksum_file_path"
  verify_sha256sum "$checksum_file_path" "$file_path"
  assert_equals "true" "$sha256sum_is_correct"

  # Checksum file format that has a filename.
  echo "$expected_sha256sum  myfile.txt" >"$checksum_file_path"
  assert_equals "true" "$sha256sum_is_correct"

  local wrong_sha256sum="cda1ee400a07d94301112707836aafaaa1760359e3cb80c9754299b82586d4ed"
  local wrong_checksum_file_path="$checksum_file_path.wrong"
  echo "$wrong_sha256sum" >"$wrong_checksum_file_path"
  verify_sha256sum "$wrong_checksum_file_path" "$file_path"
  assert_equals "false" "$sha256sum_is_correct"
}

# -------------------------------------------------------------------------------------------------
# Main test runner code

TEST_TMPDIR=/tmp/yugabyte-bash-common-test.$$.$RANDOM.$RANDOM.$RANDOM
mkdir -p "$TEST_TMPDIR"

trap cleanup EXIT

global_exit_code=0
test_fn_names=$(
  declare -F | sed 's/^declare -f //g' | grep '^yb_test_'
)

for fn_name in $test_fn_names; do
  num_assertions_succeeded_in_current_test=0
  num_assertions_failed_in_current_test=0
  fn_status="[   OK   ]"
  if ! "$fn_name" || [[ $num_assertions_failed_in_current_test -gt 0 ]]; then
    fn_status="[ FAILED ]"
    global_exit_code=1
  fi
  echo -e "$fn_status Function: $fn_name \t" \
          "Assertions succeeded: $num_assertions_succeeded_in_current_test," \
          "failed: $num_assertions_failed_in_current_test"
done

echo >&2 "Total assertions succeeded: $num_assertions_succeeded, failed: $num_assertions_failed"
if [[ $global_exit_code -eq 0 ]]; then
  echo "Tests SUCCEEDED"
else
  echo "Tests FAILED"
fi
exit "$global_exit_code"
