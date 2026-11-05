#!/bin/zsh
# Export every level picture (and the pre-built boards) from the web game into the Swift engine's levels.json.
# The pictures are painted by code in web/chipmunk-challenge.html; this runs that code in macOS's built-in
# JavaScriptCore and saves the result as plain data, so the native app never needs the HTML.
#
#   tools/export_levels.sh            # writes Engine/Sources/ChipmunkEngine/Resources/levels.json
#
# Rerun it after changing pictures or packs in the HTML, then run the engine tests.
set -euo pipefail
cd "$(dirname "$0")/.."

HTML=web/chipmunk-challenge.html
OUT=Engine/Sources/ChipmunkEngine/Resources/levels.json
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
# Coin Mining repaints its background every round; this many variants of each picture are exported.
PARADISE_VARIANTS=13

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The engine script, and the pre-built boards from the page script.
awk '/<script id="engine">/{on=1; sub(/.*<script id="engine">/, "")} on && /<\/script>/{sub(/<\/script>.*/, ""); print; exit} on{print}' "$HTML" > "$TMP/engine.js"
grep -m1 '^const BAKED=' "$HTML" > "$TMP/baked.js"
SHA=$(shasum -a 256 "$HTML" | cut -d' ' -f1)

cat > "$TMP/dump.js" <<EOF
const out={format:1,source:'$SHA',packSize:PACK_SIZE,packBonus:PACK_BONUS,rampN:RAMP_N,packs:[],paradise:[],baked:BAKED};
for(const p of PACKS){const levels=LEVELS.filter(L=>L.pack===p.id).map(L=>({id:L.id,name:L.name,rows:L.rows}));
  out.packs.push({id:p.id,name:p.name,levels})}
for(const L of LEVELS.filter(L=>L.pack==='paradise')){const variants=[];
  for(let v=0;v<$PARADISE_VARIANTS;v++){L.variant=v;variants.push(L.rows)}
  out.paradise.push({id:L.id,name:L.name,variants})}
print(JSON.stringify(out));
EOF

mkdir -p "$(dirname "$OUT")"
"$JSC" "$TMP/engine.js" "$TMP/baked.js" "$TMP/dump.js" > "$TMP/levels.json"
mv "$TMP/levels.json" "$OUT"
echo "Wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes) from $HTML"
