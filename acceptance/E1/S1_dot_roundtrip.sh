#!/usr/bin/env bash
# E1-S1 acceptance: DotWriter writes quoted labels, DOT write -> parse round-trips,
# and the existing TestDotParser runs (not skipped) and passes.
# Usage: bash acceptance/E1/S1_dot_roundtrip.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

RES=solver/build/test-results/test
CLS=acceptance.E1DotWriterRoundTripTest

if grep -nE '@Disabled|@Ignore' solver/src/test/kotlin/TestDotParser.kt; then
    fail "TestDotParser.kt contains @Disabled/@Ignore"
else
    pass "TestDotParser.kt is not disabled"
fi

# Old XML must not count: drop it, then require Gradle itself to succeed.
rm -rf "$RES"
gradle :solver:test --rerun --continue \
    --tests 'TestDotParser' --tests "$CLS" \
    > build-acceptance-S1.log 2>&1
rc=$?
echo "gradle exit code: $rc (log: build-acceptance-S1.log)"
tail -n 15 build-acceptance-S1.log
[ $rc -eq 0 ] && pass "gradle :solver:test" || fail "gradle :solver:test exit $rc"

st=$(junit_case_status "$RES" TestDotParser testParser)
[ "$st" = PASSED ] && pass "TestDotParser.testParser: $st" || fail "TestDotParser.testParser: $st"

for t in labelValuesAreQuoted bracketLabelsSurviveRoundTrip pointsToStyleLabelsSurviveRoundTrip \
         quoteInsideLabelSurvivesRoundTrip backslashInsideLabelSurvivesRoundTrip; do
    st=$(junit_case_status "$RES" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "E1DotWriterRoundTripTest.$t: $st" || fail "E1DotWriterRoundTripTest.$t: $st"
done

finish S1_dot_roundtrip
