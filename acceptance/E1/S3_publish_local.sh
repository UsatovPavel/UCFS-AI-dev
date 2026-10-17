#!/usr/bin/env bash
# E1-S3 acceptance: `publishToMavenLocal` publishes org.ucfs:solver and org.ucfs:generator
# with the fixed version, POMs whose runtime dependencies match the build, and a traceable
# jar manifest. Publishes into a fresh repository (does not touch ~/.m2). Requires E1-S2.
# Usage: bash acceptance/E1/S3_publish_local.sh     (exit 0 = PASS)
#        M2_OUT=/some/dir bash acceptance/E1/S3_publish_local.sh   (publish there instead;
#        the dir is wiped first, so it must be under build/, */acceptance/E1/out/ or a mktemp dir)
source "$(dirname "$0")/lib.sh"

M2="${M2_OUT:-$ROOT/build/acceptance-m2}"
safe_reset_dir "$M2"
M2="$(realpath "$M2")"
HEAD_SHA=$(git rev-parse HEAD)
# Tracked changes make the build "dirty"; untracked files (e.g. test-shared/gen/) do not.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then WANT_DIRTY=true; else WANT_DIRTY=false; fi
M2_BEFORE=$(m2_ucfs_snapshot)

gradle publishToMavenLocal "-Dmaven.repo.local=$M2" > build-acceptance-S3.log 2>&1
rc=$?
echo "gradle publishToMavenLocal exit code: $rc (log: build-acceptance-S3.log)"
tail -n 5 build-acceptance-S3.log
[ $rc -eq 0 ] && pass "publishToMavenLocal" || fail "publishToMavenLocal exit $rc"

[ "$(m2_ucfs_snapshot)" = "$M2_BEFORE" ] && pass "~/.m2/repository/org/ucfs unchanged" \
    || fail "~/.m2/repository/org/ucfs changed during the check (publication leaked out of $M2, or another agent published concurrently)"

for a in solver generator; do
    d="$M2/org/ucfs/$a/$UCFS_VERSION"
    jar="$d/$a-$UCFS_VERSION.jar"; pom="$d/$a-$UCFS_VERSION.pom"
    if [ ! -f "$jar" ] || [ ! -f "$pom" ]; then
        fail "$UCFS_GROUP:$a:$UCFS_VERSION not published (found: $(find "$M2" -name '*.pom' 2>/dev/null | sed "s|$M2/||" | tr '\n' ' '))"
        continue
    fi
    pass "$UCFS_GROUP:$a:$UCFS_VERSION jar and pom exist"

    python3 - "$pom" "$a" "$UCFS_VERSION" <<'PY' && pass "$a POM coordinates" || fail "$a POM coordinates"
import sys, xml.etree.ElementTree as ET
ns = {"m": "http://maven.apache.org/POM/4.0.0"}
r = ET.parse(sys.argv[1]).getroot()
got = tuple(r.findtext(f"m:{k}", namespaces=ns) for k in ("groupId", "artifactId", "version"))
print("  POM:", got)
sys.exit(0 if got == ("org.ucfs", sys.argv[2], sys.argv[3]) else 1)
PY

    mf=$(unzip -p "$jar" META-INF/MANIFEST.MF | tr -d '\r')
    echo "$mf" | grep -qx "Implementation-Version: $UCFS_VERSION" && pass "$a manifest Implementation-Version" \
        || fail "$a manifest has no 'Implementation-Version: $UCFS_VERSION'"
    echo "$mf" | grep -qx "UCFS-Commit: $HEAD_SHA" && pass "$a manifest UCFS-Commit = HEAD" \
        || fail "$a manifest has no 'UCFS-Commit: $HEAD_SHA'"
    echo "$mf" | grep -qx "UCFS-Dirty: $WANT_DIRTY" && pass "$a manifest UCFS-Dirty: $WANT_DIRTY" \
        || fail "$a manifest has no 'UCFS-Dirty: $WANT_DIRTY'"

    # The POM must list exactly the first-level runtime dependencies Gradle resolves for the
    # module (no whitelist): nothing missing, nothing extra, no 'unspecified' coordinates.
    # Project dependencies (project :solver) must be published as org.ucfs:<name>:<version>.
    gradle -q ":$a:dependencies" --configuration runtimeClasspath "-Dmaven.repo.local=$M2" \
        > "build-acceptance-S3-$a-deps.log" 2>&1 || fail ":$a:dependencies failed (build-acceptance-S3-$a-deps.log)"
    python3 - "$pom" "build-acceptance-S3-$a-deps.log" "$UCFS_VERSION" <<'PY' \
        && pass "$a POM runtime deps = Gradle runtimeClasspath first-level deps" \
        || fail "$a POM runtime deps differ from the build"
import re, sys, xml.etree.ElementTree as ET
pom, deps_log, version = sys.argv[1:4]
ns = {"m": "http://maven.apache.org/POM/4.0.0"}
pom_deps, bad = {}, []
for d in ET.parse(pom).getroot().iterfind("m:dependencies/m:dependency", ns):
    g, a, v = (d.findtext(f"m:{k}", default="", namespaces=ns).strip() for k in ("groupId", "artifactId", "version"))
    scope = d.findtext("m:scope", default="compile", namespaces=ns)
    if not g or not a or not v or v == "unspecified":
        bad.append(f"{g}:{a}:{v or '<none>'}")
    if g == "org.ucfs" and v != version:
        bad.append(f"{g}:{a}:{v} (expected version {version})")
    if scope in ("compile", "runtime"):
        pom_deps[f"{g}:{a}"] = v
declared = set()
for line in open(deps_log, encoding="utf-8", errors="replace"):
    m = re.match(r"^[+\\]--- (.+)$", line.rstrip())
    if not m or m.group(1).endswith("(c)"):
        continue
    item = m.group(1)
    pm = re.match(r"project :([\w.-]+)", item)
    if pm:
        declared.add(f"org.ucfs:{pm.group(1)}")
    else:
        declared.add(":".join(item.split()[0].split(":")[:2]))
print("  POM compile/runtime deps:", dict(sorted(pom_deps.items())))
print("  Gradle runtimeClasspath first-level:", sorted(declared))
missing, extra = sorted(declared - set(pom_deps)), sorted(set(pom_deps) - declared)
if missing: print("  missing in POM:", missing)
if extra: print("  extra in POM:", extra)
if bad: print("  bad coordinates:", bad)
sys.exit(0 if declared and not missing and not extra and not bad else 1)
PY
done

pom="$M2/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.pom"
if [ -f "$pom" ]; then
    jar="${pom%.pom}.jar"
    python3 - "$jar" <<'PY' && pass "solver jar has Gll/DotParser, bytecode <= Java 21" || fail "solver jar content/bytecode"
import sys, zipfile, struct
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
need = ["org/ucfs/parser/Gll.class", "org/ucfs/input/DotParser.class", "org/ucfs/rsm/RsmState.class"]
missing = [n for n in need if n not in names]
major = struct.unpack(">H", z.read(need[0])[6:8])[0] if not missing else None
print("  missing:", missing, "class major:", major)
sys.exit(0 if not missing and major <= 65 else 1)
PY
fi

# Presence only; whether the README section is usable is judged by the verifier (E1-S3 DoD).
grep -q 'publishToMavenLocal' README.md && grep -qF "$UCFS_VERSION" README.md \
    && pass "README mentions publishToMavenLocal and $UCFS_VERSION" \
    || fail "README does not mention publishToMavenLocal / $UCFS_VERSION"

finish S3_publish_local
