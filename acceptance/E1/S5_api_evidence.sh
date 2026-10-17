#!/usr/bin/env bash
# E1-S5 evidence generator (pre-committed by the planner, so the evidence does not depend on
# the implementer's tooling). It compares the public API of the published solver with the two
# jars cfl-idr-with-gll ships, and compiles disposable copies of cfl-idr against the published
# artifact with cfl-idr's OWN Gradle wrapper (8.14), so that a failure is a compiler outcome and
# not a "Kotlin 1.9 plugin on Gradle 9" configuration error.
#
# Variants (each one is a fresh `git archive HEAD` copy of cfl-idr; the cfl-idr repo is untouched):
#   V0 control: cfl-idr as is (libs/solver-new.jar, Kotlin 1.9.20) - must compile, else the harness is broken
#   V1: dependency org.ucfs:solver:<version> from M2 instead of libs/solver-new.jar, Kotlin 1.9.20
#   V2: as V1, but kotlin("jvm") 2.4.0 (same compiler as UCFS) - shows pure API differences
# Tasks: compileKotlin compileTestKotlin. Outcome: SUCCESS | COMPILER_ERRORS(<n e: lines>) | GRADLE_ERROR.
#
# Usage: bash acceptance/E1/S5_api_evidence.sh <cfl-idr checkout> [M2 with published solver]
#        (M2 defaults to build/acceptance-m2, the output of S3_publish_local.sh)
# Output: acceptance/E1/out/S5/ (summary.txt, api-*.txt, diff-*.txt, V*.log, unresolved-V2.txt)
# Exit: 0 = evidence complete (V0 SUCCESS, no GRADLE_ERROR), 1 = evidence invalid, 2 = precondition.
source "$(dirname "$0")/lib.sh"

CFL="${1:?usage: S5_api_evidence.sh <cfl-idr checkout> [M2]}"
CFL="$(cd "$CFL" && pwd)" || die_env "no such dir: $1"
M2="$(realpath -m "${2:-$ROOT/build/acceptance-m2}")"
PUB="$M2/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.jar"
[ -f "$PUB" ] || die_env "precondition: $PUB not found; run acceptance/E1/S3_publish_local.sh first"
[ -f "$CFL/build.gradle.kts" ] && [ -f "$CFL/libs/solver-new.jar" ] && [ -f "$CFL/libs/solver-original.jar" ] \
    || die_env "$CFL does not look like cfl-idr-with-gll (build.gradle.kts, libs/solver-{new,original}.jar)"
JAVAP="$JAVA_HOME/bin/javap"; [ -x "$JAVAP" ] || die_env "no javap in JAVA_HOME=$JAVA_HOME"

OUT="$ROOT/acceptance/E1/out/S5"
safe_reset_dir "$OUT"
CFL_SHA=$(git -C "$CFL" rev-parse HEAD)
UCFS_COMMIT=$(unzip -p "$PUB" META-INF/MANIFEST.MF | tr -d '\r' | sed -n 's/^UCFS-Commit: //p')
{
    echo "cfl-idr: $CFL_SHA ($CFL)"
    echo "published solver: $PUB"
    echo "published UCFS-Commit: ${UCFS_COMMIT:-<none>}"
} > "$OUT/summary.txt"

# --- 1. Public API dumps: one line per "<class> | <member or header>", sorted --------------
api_dump() { # jar out
    python3 - "$JAVAP" "$1" "$2" <<'PY'
import subprocess, sys, zipfile
javap, jar, out = sys.argv[1:4]
classes = sorted(n[:-6].replace("/", ".") for n in zipfile.ZipFile(jar).namelist()
                 if n.startswith("org/ucfs/") and n.endswith(".class"))
lines = []
for i in range(0, len(classes), 200):
    txt = subprocess.run([javap, "-public", "-cp", jar] + classes[i:i + 200],
                         capture_output=True, text=True, check=True).stdout
    cls = None
    for raw in txt.splitlines():
        s = raw.strip()
        if not s or s.startswith("Compiled from"):
            continue
        if s.endswith("{"):
            cls = s[:-1].strip()
            name = next((t for t in cls.replace("<", " ").split() if t.startswith("org.ucfs.")), cls)
            lines.append(f"{name} | {cls}")
        elif s == "}":
            cls = None
        elif cls:
            lines.append(f"{name} | {s}")
open(out, "w").write("\n".join(sorted(set(lines))) + "\n")
print(f"  {jar}: {len(classes)} classes, {len(set(lines))} public API lines")
PY
}
ok=1
api_dump "$CFL/libs/solver-new.jar" "$OUT/api-solver-new.txt" || ok=0
api_dump "$CFL/libs/solver-original.jar" "$OUT/api-solver-original.txt" || ok=0
api_dump "$PUB" "$OUT/api-published.txt" || ok=0
[ $ok = 1 ] && pass "public API dumps of 3 jars" || fail "javap dump failed"
diff "$OUT/api-solver-new.txt" "$OUT/api-published.txt" > "$OUT/diff-solver-new-vs-published.txt"
diff "$OUT/api-solver-original.txt" "$OUT/api-published.txt" > "$OUT/diff-solver-original-vs-published.txt"
for f in diff-solver-new-vs-published diff-solver-original-vs-published; do
    echo "$f: $(grep -c '^<' "$OUT/$f.txt") only-left, $(grep -c '^>' "$OUT/$f.txt") only-published" | tee -a "$OUT/summary.txt"
done

# --- 2. Compile disposable copies of cfl-idr -----------------------------------------------
make_copy() { # variant kotlin-version use-published(0/1)
    local dir="$OUT/cfl-idr-$1"
    mkdir -p "$dir" && git -C "$CFL" archive HEAD | tar -x -C "$dir" || return 1
    python3 - "$dir/build.gradle.kts" "$2" "$3" "$M2" "$UCFS_VERSION" <<'PY'
import sys
path, kver, use_pub, m2, ver = sys.argv[1:6]
s = open(path).read()
def sub(old, new):
    global s
    if old not in s:
        sys.exit(f"pattern not found in build.gradle.kts: {old}")
    s = s.replace(old, new, 1)
sub('kotlin("jvm") version "1.9.20"', f'kotlin("jvm") version "{kver}"')
if use_pub == "1":
    sub('implementation(files("libs/solver-new.jar"))', f'implementation("org.ucfs:solver:{ver}")')
    sub("repositories {\n\tmavenCentral()",
        "repositories {\n\tmaven {\n\t\turl = uri(\"" + "file://" + m2 + "\")\n"
        "\t\tcontent { includeGroup(\"org.ucfs\") }\n\t}\n\tmavenCentral()")
open(path, "w").write(s)
PY
}

compile_variant() { # variant kotlin-version use-published
    local v=$1 dir="$OUT/cfl-idr-$1" log="$OUT/$1.log" rc outcome n
    if ! make_copy "$@" > "$log" 2>&1; then
        echo "$v: GRADLE_ERROR (copy/patch failed, see $v.log)" | tee -a "$OUT/summary.txt"; return
    fi
    (cd "$dir" && bash ./gradlew --console=plain --no-build-cache compileKotlin compileTestKotlin --continue) >> "$log" 2>&1
    rc=$?
    n=$(grep -c '^e: ' "$log")
    if [ $rc -eq 0 ]; then outcome=SUCCESS
    elif [ "$n" -gt 0 ]; then outcome="COMPILER_ERRORS($n)"
    else outcome=GRADLE_ERROR
    fi
    echo "$v: $outcome" | tee -a "$OUT/summary.txt"
    echo "$v e: main=$(grep -cE '^e: file://[^ ]*/src/main/' "$log") test=$(grep -cE '^e: file://[^ ]*/src/test/' "$log")" \
        | tee -a "$OUT/summary.txt"
}

compile_variant V0 1.9.20 0
compile_variant V1 1.9.20 1
compile_variant V2 2.4.0 1

grep -oE "binary version of its metadata is [0-9.]+, expected version is [0-9.]+" "$OUT/V1.log" | sort | uniq -c \
    | sed 's/^/V1 metadata: /' | tee -a "$OUT/summary.txt"
grep -oE "Unresolved reference:? '?[A-Za-z_][A-Za-z0-9_]*'?" "$OUT/V2.log" \
    | sed -E "s/Unresolved reference:? '?([A-Za-z0-9_]+)'?/\1/" | sort -u > "$OUT/unresolved-V2.txt"
echo "V2 unresolved symbols: $(wc -l < "$OUT/unresolved-V2.txt") ($(tr '\n' ' ' < "$OUT/unresolved-V2.txt"))" | tee -a "$OUT/summary.txt"

grep -qx 'V0: SUCCESS' "$OUT/summary.txt" && pass "V0 control compiles (harness works)" \
    || fail "V0 control does not compile: evidence invalid (see $OUT/V0.log)"
grep -q ': GRADLE_ERROR' "$OUT/summary.txt" && fail "a variant ended with a Gradle (not compiler) error, see $OUT/V*.log" \
    || pass "every variant ended with a compiler outcome"
echo "--- $OUT/summary.txt"; cat "$OUT/summary.txt"
finish S5_api_evidence
