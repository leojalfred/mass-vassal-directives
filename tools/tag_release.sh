#!/usr/bin/env bash
# Creates a release tag whose message is that version's patch notes, so the
# release the workflow publishes carries them.
#
#   bash tools/tag_release.sh <tag> [commit]
#
#   tag     vanilla-vX.Y.Z, agot-vX.Y.Z or tfe-vX.Y.Z
#   commit  what to tag (default: HEAD). Tag the commit that was published to
#           the Workshop.
#
# The notes are the plain-text (Paradox Mods) block of
# publishing/patch_notes/<mod>-<version>.md, where <mod> is base, agot or tfe.
# publishing/ is not in git, so the release workflow cannot read the patch notes
# itself; the tag message is how they reach it. The tag is created locally and
# not pushed, so it can be checked first.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=${1:?usage: tag_release.sh <tag> [commit]}
COMMIT=${2:-HEAD}

case $TAG in
	vanilla-v*) TARGET=vanilla; NOTES_MOD=base; DESC=descriptor.mod ;;
	agot-v*)    TARGET=agot;    NOTES_MOD=agot; DESC=agot/descriptor.mod ;;
	tfe-v*)     TARGET=tfe;     NOTES_MOD=tfe;  DESC=tfe/descriptor.mod ;;
	*) echo "tag must start with vanilla-v, agot-v or tfe-v: $TAG" >&2; exit 1 ;;
esac
VER=${TAG#*-v}

# Caught here rather than in the workflow, where a mismatch would only surface
# after the tag was pushed.
MOD_VER=$(git show "$COMMIT:$DESC" | grep -m1 '^version=' | sed -E 's/^version="([^"]*)".*/\1/')
[ "$MOD_VER" = "$VER" ] || { echo "$COMMIT builds $TARGET $MOD_VER, not $VER" >&2; exit 1; }
if [ "$TARGET" != vanilla ] && ! git cat-file -e "$COMMIT:$TARGET/tested_with" 2>/dev/null; then
	echo "$COMMIT has no $TARGET/tested_with, which its release needs" >&2; exit 1
fi

NOTES_FILE="publishing/patch_notes/$NOTES_MOD-$VER.md"
[ -f "$NOTES_FILE" ] || { echo "no patch notes at $NOTES_FILE" >&2; exit 1; }
# The second fenced block after the "## Paradox Mods" heading's opening fence:
# everything between that heading's ``` lines.
NOTES=$(awk '/^## Paradox Mods/{p=1; next} p && /^```/{if (q) exit; q=1; next} p && q' "$NOTES_FILE")
[ -n "$(echo "$NOTES" | tr -d '[:space:]')" ] || { echo "no plain-text block under '## Paradox Mods' in $NOTES_FILE" >&2; exit 1; }

printf '%s\n' "$NOTES" | git tag -a "$TAG" "$COMMIT" -F - --cleanup=verbatim
echo "tagged $TAG at $(git rev-parse --short "$COMMIT^{commit}") with the notes from $NOTES_FILE"
echo "check it with:  git show $TAG"
echo "publish it with: git push origin $TAG"
