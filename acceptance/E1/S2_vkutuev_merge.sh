#!/usr/bin/env bash
# E1-S2 acceptance: vkutuev/main (publishing, JaCoCo, Gradle 9.6.1, Kotlin 2.4.0) is merged
# into our main without losing our commits, and the full build with all tests is green
# without new @Disabled/@Ignore. Requires E1-S1 (TestDotParser must pass).
# Usage: bash acceptance/E1/S2_vkutuev_merge.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

VKUTUEV_TIP=b0c089d   # vkutuev/main at planning time (2026-10-18)
OUR_BASE=ebb5e16      # UCFS-AI-dev main at planning time

git cat-file -e "$VKUTUEV_TIP^{commit}" 2>/dev/null || die_env "commit $VKUTUEV_TIP not found (git fetch vkutuev)"

git merge-base --is-ancestor "$VKUTUEV_TIP" HEAD && pass "vkutuev/main $VKUTUEV_TIP is merged" \
    || fail "vkutuev/main $VKUTUEV_TIP is not an ancestor of HEAD"
git merge-base --is-ancestor "$OUR_BASE" HEAD && pass "our main $OUR_BASE is kept" \
    || fail "$OUR_BASE is not an ancestor of HEAD"

grep -q 'gradle-9\.6\.1-' gradle/wrapper/gradle-wrapper.properties && pass "wrapper is Gradle 9.6.1" \
    || fail "wrapper is not Gradle 9.6.1: $(grep distributionUrl gradle/wrapper/gradle-wrapper.properties)"

if [ -f build.gradle.kts ]; then
    grep -q 'kotlin("jvm") version "2.4.0"' build.gradle.kts && pass "root declares Kotlin 2.4.0" || fail "root build.gradle.kts does not declare Kotlin 2.4.0"
    grep -q 'maven-publish' build.gradle.kts && pass "root applies maven-publish" || fail "root build.gradle.kts has no maven-publish"
    grep -q 'jacoco-report-aggregation' build.gradle.kts && pass "root applies jacoco-report-aggregation" || fail "no jacoco-report-aggregation"
else
    fail "root build.gradle.kts is missing"
fi
grep -q 'include("cfpq-paths-app")' settings.gradle.kts && pass "cfpq-paths-app still included" || fail "cfpq-paths-app dropped from settings.gradle.kts"

# No new disabled tests: only the two classes disabled on ebb5e16 may carry @Disabled/@Ignore.
extra=$(grep -rlE '@Disabled|@Ignore' --include='*.kt' --include='*.java' . 2>/dev/null \
    | grep -v '/build/' | grep -vE '^\./solver/src/test/kotlin/rsm/(api/TerminalsEqualsTest|builder/AStarTest)\.kt$')
[ -z "$extra" ] && pass "no new @Disabled/@Ignore" || fail "new @Disabled/@Ignore in: $extra"

gradle clean build --continue > build-acceptance-S2.log 2>&1
rc=$?
echo "gradle clean build exit code: $rc (log: build-acceptance-S2.log)"
tail -n 5 build-acceptance-S2.log
[ $rc -eq 0 ] && pass "gradle clean build" || fail "gradle clean build exit $rc"

st=$(junit_case_status solver/build/test-results/test TestDotParser testParser)
[ "$st" = PASSED ] && pass "TestDotParser.testParser: $st" || fail "TestDotParser.testParser: $st"

check_module() { # module min_tests max_skipped
    read -r t s f e <<<"$(junit_summary "$1/build/test-results/test")"
    echo "  $1: tests=$t skipped=$s failures=$f errors=$e"
    if [ "$t" -ge "$2" ] && [ "$s" -le "$3" ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ]; then
        pass "$1 tests (>= $2 run, <= $3 skipped, 0 failed)"
    else
        fail "$1 tests (need >= $2 run, <= $3 skipped, 0 failed)"
    fi
}
check_module solver 9 4          # 5 on ebb5e16 (4 skipped) + 4 acceptance tests
check_module test-shared 16 0
check_module cfpq-paths-app 6 0

gradle testCodeCoverageReport > build-acceptance-S2-jacoco.log 2>&1
rc=$?
[ $rc -eq 0 ] && [ -f build/reports/jacoco/testCodeCoverageReport/testCodeCoverageReport.xml ] \
    && pass "testCodeCoverageReport produced" || fail "testCodeCoverageReport failed (exit $rc)"

finish S2_vkutuev_merge
