#!/usr/bin/env bash
# Packages one built mod as a GitHub release: a zip a player can unpack straight
# into their CK3 mod folder, plus the release's title and notes.
#
#   bash tools/package_release.sh <tag> [out dir]
#
#   tag      vanilla-vX.Y.Z, agot-vX.Y.Z or tfe-vX.Y.Z. The prefix picks the mod,
#            and the version must match that mod's descriptor.mod.
#   out dir  where the zip, title.txt, notes.md and latest.txt land
#            (default: dist/release).
#
# Why releases exist at all: Steam updates a subscribed mod whatever game
# version its player is on, so someone who rolls CK3 back is handed a mod built
# for the new version. A release per mod version gives them one that matches.
#
# The zip is a local mod, not a Workshop copy: a versioned folder plus the .mod
# file the launcher needs to find it, a name that says which version it is, and
# no remote_file_id, which would tie it to the Workshop item and let the
# launcher confuse the two.
#
# A total-conversion build also names the version of that conversion it was
# tested with, read from agot/tested_with or tfe/tested_with: one line holding
# the version exactly as the conversion's own descriptor.mod gives it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

TAG=${1:?usage: package_release.sh <tag> [out dir]}
OUT=${2:-$ROOT/dist/release}

case $TAG in
	vanilla-v*) TARGET=vanilla; LABEL="Base mod" ;;
	agot-v*)    TARGET=agot;    LABEL="A Game of Thrones build"; TC_NAME="A Game of Thrones"; TC_SHORT=AGOT ;;
	tfe-v*)     TARGET=tfe;     LABEL="The Fallen Eagle build";  TC_NAME="The Fallen Eagle";  TC_SHORT=TFE ;;
	*) echo "tag must start with vanilla-v, agot-v or tfe-v: $TAG" >&2; exit 1 ;;
esac
VER=${TAG#*-v}

desc_field() { grep -m1 "^$1=" "$2" | sed -E 's/^[a-z_]+="([^"]*)".*/\1/'; }

# A conversion build is only as good as the conversion it was checked against,
# so it does not ship without saying which one.
TC_VER=
if [ "$TARGET" != vanilla ]; then
	[ -f "$TARGET/tested_with" ] && TC_VER=$(tr -d '[:space:]' < "$TARGET/tested_with")
	[ -n "$TC_VER" ] || { echo "no $TC_NAME version recorded: write the one this build was tested with to $TARGET/tested_with" >&2; exit 1; }
fi

echo "building ..."
bash tools/build.sh
DIST="$ROOT/dist/$TARGET"
DESC="$DIST/descriptor.mod"

# A tag is a promise about what is inside, so it has to agree with the mod.
MOD_VER=$(desc_field version "$DESC")
[ "$MOD_VER" = "$VER" ] || { echo "tag $TAG says $VER but $TARGET's descriptor.mod says $MOD_VER" >&2; exit 1; }
# "1.19.*" reads as "1.19.x" in a title.
CK3=$(desc_field supported_version "$DESC" | sed 's/\*/x/')
NAME=$(desc_field name "$DESC")

# The folder and .mod file are named for the version, so several can sit side
# by side in one mod folder and a player can tell them apart in the launcher.
DIR="leo_mvd_${TARGET}_${VER}"
rm -rf "$OUT"; mkdir -p "$OUT/stage/$DIR"
cp -r "$DIST/." "$OUT/stage/$DIR/"
LOCAL_NAME="$NAME (v$VER)"
sed -i -e '/^remote_file_id=/d' -e "s/^name=.*/name=\"$LOCAL_NAME\"/" "$OUT/stage/$DIR/descriptor.mod"
# The launcher reads mod/*.mod, which is the descriptor plus where to find it.
# path is relative to the CK3 user folder, so it works wherever that lives.
{ cat "$OUT/stage/$DIR/descriptor.mod"; printf '\npath="mod/%s"\n' "$DIR"; } > "$OUT/stage/$DIR.mod"

ZIP="mvd-$TARGET-v$VER.zip"
if command -v zip >/dev/null; then
	(cd "$OUT/stage" && zip -qr "$OUT/$ZIP" "$DIR" "$DIR.mod")
elif [ -x /c/Windows/System32/tar.exe ]; then
	# Windows' own tar writes zips, for building a release by hand there.
	(cd "$OUT/stage" && /c/Windows/System32/tar.exe -a -cf "$(cygpath -w "$OUT/$ZIP")" "$DIR" "$DIR.mod")
else
	echo "no zip tool found" >&2; exit 1
fi

TITLE="$LABEL v$VER (CK3 $CK3"
[ -n "$TC_VER" ] && TITLE="$TITLE, $TC_SHORT $TC_VER"
TITLE="$TITLE)"
echo "$TITLE" > "$OUT/title.txt"

# Only the newest base-mod release is marked Latest. The three mods share one
# release list, and a conversion build or an older version tagged late should
# never push the current base mod off the top of it.
NEWEST=$(git tag -l 'vanilla-v*' | sort -V | tail -1)
if [ "$TARGET" = vanilla ] && { [ -z "$NEWEST" ] || [ "$NEWEST" = "$TAG" ]; }; then echo true; else echo false; fi > "$OUT/latest.txt"

{
	echo "**$NAME**, version $VER."
	echo
	echo "- Crusader Kings III: **$CK3**"
	if [ -n "$TC_VER" ]; then echo "- $TC_NAME: tested with **$TC_VER**"; fi
	echo
	echo "This is for players whose game is not on the version the Steam Workshop copy supports, for example after rolling Crusader Kings III back. If your game is current, subscribe on the Workshop instead."
	echo
	echo "### Installing"
	echo
	echo "1. Unsubscribe from the Workshop version, or Steam will keep updating it and both will show up."
	echo "2. Unzip \`$ZIP\` into \`Documents/Paradox Interactive/Crusader Kings III/mod/\`, so that \`$DIR\` and \`$DIR.mod\` sit side by side there."
	if [ -n "$TC_VER" ]; then
		echo "3. In the launcher, add **$LOCAL_NAME** to your playset. Load it after $TC_NAME."
	else
		echo "3. In the launcher, add **$LOCAL_NAME** to your playset."
	fi
	# An annotated tag's message is the release's patch notes.
	if [ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null)" = tag ]; then
		NOTES=$(git tag -l --format='%(contents:subject)%0a%0a%(contents:body)' "$TAG")
		if [ -n "$(echo "$NOTES" | tr -d '[:space:]')" ]; then
			echo
			echo "### Changes"
			echo
			echo "$NOTES"
		fi
	fi
} > "$OUT/notes.md"

rm -rf "$OUT/stage"
echo "packaged $OUT/$ZIP"
echo "title:  $TITLE"
echo "latest: $(cat "$OUT/latest.txt")"
