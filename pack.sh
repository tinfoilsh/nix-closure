#!/usr/bin/env bash
# Stages a nix closure into a store tree modelwrap can pack, then packs it.
set -euo pipefail

ATTR="${1:-.#closure}"
STAGE="${STAGE:-$PWD/stage}"

closure="$(nix build --no-link --print-out-paths "$ATTR")"
if [ "$(printf '%s\n' "$closure" | wc -l)" -ne 1 ]; then
	echo "$ATTR must produce exactly one output path" >&2
	exit 1
fi

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

# registrationTime is when nix copied each path, so it would put a clock in
# the root hash. Flatten it and rewrite the file in one page order.
nix shell --no-write-lock-file .#sqlite -c sqlite3 "$STAGE/nix/var/nix/db/db.sqlite" \
	"update ValidPaths set registrationTime = 1; pragma journal_mode = delete; vacuum;"

storeName="${closure#/nix/store/}"
model="nix/${storeName#*-}@${storeName%%-*}"

echo "Packing $model"
exec modelwrap --model-dir "$STAGE" "$model"
