#!/usr/bin/env bash
# E1-S1 acceptance: DotWriter writes quoted labels, DOT write -> parse round-trips,
# and the existing TestDotParser runs (not skipped) and passes.
# Usage: bash acceptance/E1/S1_dot_roundtrip.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

RES=solver/build/test-results/test

if grep -nE '@Disabled|@Ignore' solver/src/test/kotlin/TestDotParser.kt; then
    fail "TestDotParser.kt contains @Disabled/@Ignore"
else
    pass "TestDotParser.kt is not disabled"
fi

gradle :solver:test --rerun --continue \
    --tests 'TestDotParser' --tests 'acceptance.E1DotWriterRoundTripTest' \
    > build-acceptance-S1.log 2>&1
echo "gradle exit code: $? (log: build-acceptance-S1.log)"
tail -n 15 build-acceptance-S1.log

st=$(junit_case_status "$RES" TestDotParser testParser)
[ "$st" = PASSED ] && pass "TestDotParser.testParser: $st" || fail "TestDotParser.testParser: $st"

for t in labelValuesAreQuoted bracketLabelsSurviveRoundTrip pointsToStyleLabelsSurviveRoundTrip quoteInsideLabelSurvivesRoundTrip; do
    st=$(junit_case_status "$RES" acceptance.E1DotWriterRoundTripTest "$t")
    [ "$st" = PASSED ] && pass "E1DotWriterRoundTripTest.$t: $st" || fail "E1DotWriterRoundTripTest.$t: $st"
done

finish S1_dot_roundtrip
