#!/usr/bin/env bash
# E1-S3 acceptance: `publishToMavenLocal` publishes org.ucfs:solver and org.ucfs:generator
# with the fixed version, a POM with runtime dependencies, and a traceable jar manifest.
# Publishes into a fresh repository under build/ (does not touch ~/.m2). Requires E1-S2.
# Usage: bash acceptance/E1/S3_publish_local.sh     (exit 0 = PASS)
#        M2_OUT=/some/dir bash acceptance/E1/S3_publish_local.sh   (publish there instead)
source "$(dirname "$0")/lib.sh"

M2="${M2_OUT:-$ROOT/build/acceptance-m2}"
rm -rf "$M2"; mkdir -p "$M2"
HEAD_SHA=$(git rev-parse HEAD)

gradle publishToMavenLocal "-Dmaven.repo.local=$M2" > build-acceptance-S3.log 2>&1
rc=$?
echo "gradle publishToMavenLocal exit code: $rc (log: build-acceptance-S3.log)"
tail -n 5 build-acceptance-S3.log
[ $rc -eq 0 ] && pass "publishToMavenLocal" || fail "publishToMavenLocal exit $rc"

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
done

pom="$M2/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.pom"
if [ -f "$pom" ]; then
    python3 - "$pom" <<'PY' && pass "solver POM lists runtime deps" || fail "solver POM misses runtime deps"
import sys, xml.etree.ElementTree as ET
ns = {"m": "http://maven.apache.org/POM/4.0.0"}
deps = {}
for d in ET.parse(sys.argv[1]).getroot().iterfind("m:dependencies/m:dependency", ns):
    deps[d.findtext("m:artifactId", namespaces=ns)] = d.findtext("m:scope", default="compile", namespaces=ns)
print("  deps:", deps)
need = ["kotlin-stdlib", "antlr4", "kotlin-logging-jvm"]
sys.exit(0 if all(deps.get(n) in ("compile", "runtime") for n in need) else 1)
PY
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

grep -q 'publishToMavenLocal' README.md && grep -qF "$UCFS_VERSION" README.md \
    && pass "README documents publishToMavenLocal and $UCFS_VERSION" \
    || fail "README does not document publishToMavenLocal / $UCFS_VERSION"

finish S3_publish_local
