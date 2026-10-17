#!/usr/bin/env bash
# E1-S5 check of the report against the evidence of S5_api_evidence.sh (run that first).
# The note must: name the measured artifact (UCFS-Commit) and cfl-idr commit; quote the outcome
# of every compile variant verbatim ("V1: COMPILER_ERRORS(20)", "V1 e: main=20 test=0"); have a row for EVERY symbol
# that V2 reports as unresolved; label conclusions "проверено"/"интерпретация"; and end with a
# recommendation for E6. It does not judge whether the analysis is right: that is the verifier's job.
# Usage: bash acceptance/E1/S5_note_check.sh <note.md>     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

NOTE="${1:?usage: S5_note_check.sh <note.md>}"
EV="$ROOT/acceptance/E1/out/S5"
[ -f "$EV/summary.txt" ] || die_env "no $EV/summary.txt: run acceptance/E1/S5_api_evidence.sh first"
[ -f "$NOTE" ] || { fail "note $NOTE not found"; finish S5_note_check; }

for key in "published UCFS-Commit" "cfl-idr"; do
    sha=$(sed -n "s/^$key: \([0-9a-f]\{7,40\}\).*/\1/p" "$EV/summary.txt" | head -n1)
    [ -n "$sha" ] && grep -q "${sha:0:7}" "$NOTE" && pass "note names $key ${sha:0:7}" \
        || fail "note does not name $key ${sha:0:7}"
done
while read -r line; do
    grep -qF "$line" "$NOTE" && pass "note quotes '$line'" || fail "note does not quote '$line'"
done < <(grep -E '^V[0-9]:? ' "$EV/summary.txt" | grep -E '^V[0-9](:| e:) ')
missing=""
while read -r sym; do
    [ -z "$sym" ] && continue
    grep -qE "(^|[^A-Za-z0-9_])$sym([^A-Za-z0-9_]|$)" "$NOTE" || missing="$missing $sym"
done < "$EV/unresolved-V2.txt"
[ -z "$missing" ] && pass "every V2 unresolved symbol ($(wc -l < "$EV/unresolved-V2.txt")) is in the note" \
    || fail "V2 unresolved symbols missing from the note:$missing"
grep -q 'проверено' "$NOTE" && grep -q 'интерпретация' "$NOTE" && pass "conclusions are labelled" \
    || fail "note lacks 'проверено'/'интерпретация' labels"
grep -qE '^## .*E6' "$NOTE" && pass "note has a recommendation section for E6" || fail "no '## ... E6' section"
finish S5_note_check
