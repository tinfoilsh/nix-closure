#!/usr/bin/env bash
# Stages a nix closure into a store tree modelwrap can pack, then packs it.
set -euo pipefail

ATTR="${1:-.#closure}"
STAGE="${STAGE:-$PWD/stage}"
FLAKE="${ATTR%%#*}"

build() { nix build --no-update-lock-file --no-link --print-out-paths "$@"; }

closure="$(build "$ATTR")"
if [ "$(printf '%s\n' "$closure" | wc -l)" -ne 1 ]; then
	echo "$ATTR must produce exactly one output path" >&2
	exit 1
fi

# The store db schema and the order it assigns row ids are specific to the nix
# that writes them, so the packer has to be the nix the closure carries rather
# than whatever is on PATH.
nixstore="$(build "$FLAKE#nix^out")/bin/nix-store"
sqlite3="$(build "$FLAKE#sqlite^bin")/bin/sqlite3"

# cp or tar would carry the source host's hardlinks and modes into the root
# hash. auto-optimise-store hardlinks duplicate files, so pass it explicitly
# instead of taking whatever the staging host's nix.conf says.
if [ -e "$STAGE" ]; then
	chmod -R u+w "$STAGE"
	rm -rf "$STAGE"
fi
nix copy --no-check-sigs --option auto-optimise-store false \
	--to "local?root=$STAGE" "$closure"

# Host state, not closure content.
rm -rf "$STAGE/nix/store/.links"

# The copied db records copy order, substituter signatures and gc roots, which
# are all facts about the staging host. --dump-db emits only closure facts, in
# path order, so reloading it rebuilds the db as a function of the closure.
dump="$(mktemp)"
"$nixstore" --store "local?root=$STAGE" --dump-db > "$dump"
rm -rf "$STAGE/nix/var"
"$nixstore" --store "local?root=$STAGE" --load-db < "$dump"
rm -f "$dump"

# registrationTime is when nix registered each path, so it would put a clock in
# the root hash. Flatten it and rewrite the file in one page order.
db="$STAGE/nix/var/nix/db"
"$sqlite3" "$db/db.sqlite" \
	"update ValidPaths set registrationTime = 1; pragma journal_mode = delete; vacuum;"

# Scratch a writable store keeps: sqlite side files, and a reserve whose size
# follows the packer's nix.conf. The pack is only ever the read-only half.
rm -f "$db/db.sqlite-wal" "$db/db.sqlite-shm" "$db/reserved"

storeName="${closure#/nix/store/}"
model="nix/${storeName#*-}@${storeName%%-*}"

echo "Packing $model"
exec modelwrap --model-dir "$STAGE" "$model"
