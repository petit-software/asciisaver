#!/bin/bash
#
# Builds, signs, notarizes and publishes a GitHub release.
#
# Usage:
#   ./scripts/release.sh v1.0.0
#
# Notarization credentials, in the order this script tries them:
#
#   1. App Store Connect API key (preferred, no app-specific password):
#        export NOTARY_API_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_<id>.p8"
#        export NOTARY_API_KEY_ID="<key-id>"
#        export NOTARY_API_ISSUER="<issuer-uuid>"
#      These are the same names the other projects on this machine use.
#
#   2. A stored notarytool keychain profile:
#        NOTARY_PROFILE=ASCIISaver ./scripts/release.sh v1.0.0
#      Create once with:
#        xcrun notarytool store-credentials "ASCIISaver" \
#          --apple-id "bartosz.bak@me.com" --team-id "TJ3ALYQV5G" \
#          --keychain "$HOME/Library/Keychains/login.keychain-db"
#
#   3. NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER, passed straight through.
#
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:-}"
if [ -z "$TAG" ]; then
	echo "Usage: $0 <tag>   e.g. $0 v1.0.0" >&2
	exit 1
fi

PRODUCT="ASCIISaver.saver"
BUILT="build/Build/Products/Release/$PRODUCT"
DIST="dist"
ZIP="$DIST/ASCIISaver-$TAG.zip"

# --- Build ------------------------------------------------------------------
echo "==> Building $TAG"
./build.sh >/dev/null

if [ ! -d "$BUILT" ]; then
	echo "Build produced no $PRODUCT" >&2
	exit 1
fi

# --- Verify the signature is notarizable ------------------------------------
echo "==> Verifying signature"
codesign --verify --strict --deep --verbose=2 "$BUILT"

# Captured to a variable rather than piped into grep: `grep -q` exits at the
# first match, codesign takes SIGPIPE, and `pipefail` would report the whole
# pipeline as failed even though the pattern matched.
SIGN_INFO="$(codesign -dvv "$BUILT" 2>&1)"

case "$SIGN_INFO" in
	*"Authority=Developer ID Application"*) ;;
	*)
		echo "Not signed with a Developer ID; notarization would be rejected." >&2
		exit 1
		;;
esac

case "$SIGN_INFO" in
	*runtime*) ;;
	*)
		echo "Hardened runtime is not enabled; notarization would be rejected." >&2
		exit 1
		;;
esac

# --- Package ----------------------------------------------------------------
echo "==> Packaging $ZIP"
mkdir -p "$DIST"
rm -f "$ZIP"
# ditto preserves the bundle's symlinks and extended attributes; `zip` does not.
ditto -c -k --keepParent "$BUILT" "$ZIP"

# --- Notarize ---------------------------------------------------------------
echo "==> Notarizing (this takes a few minutes)"

# Prefer the App Store Connect API key; fall back to a keychain profile.
# The profile path is pinned to the login keychain on purpose: without an
# explicit --keychain, notarytool intermittently reports "No Keychain password
# item found for profile" even when the profile exists.
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if [ -n "${NOTARY_API_KEY:-}" ] && [ -n "${NOTARY_API_KEY_ID:-}" ] && [ -n "${NOTARY_API_ISSUER:-}" ]; then
	# Same env var names the other projects on this machine use.
	xcrun notarytool submit "$ZIP" \
		--key "$NOTARY_API_KEY" \
		--key-id "$NOTARY_API_KEY_ID" \
		--issuer "$NOTARY_API_ISSUER" \
		--wait
elif [ -n "${NOTARY_PROFILE:-}" ]; then
	xcrun notarytool submit "$ZIP" \
		--keychain-profile "$NOTARY_PROFILE" \
		--keychain "$NOTARY_KEYCHAIN" \
		--wait
elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
	xcrun notarytool submit "$ZIP" \
		--key "$NOTARY_KEY" \
		--key-id "$NOTARY_KEY_ID" \
		--issuer "$NOTARY_ISSUER" \
		--wait
else
	echo "No notarization credentials. Set one of:" >&2
	echo "  NOTARY_API_KEY + NOTARY_API_KEY_ID + NOTARY_API_ISSUER  (preferred)" >&2
	echo "  NOTARY_PROFILE          (a stored notarytool keychain profile)" >&2
	echo "  NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER" >&2
	exit 1
fi

# --- Staple -----------------------------------------------------------------
# The ticket is stapled to the bundle, then the bundle is re-zipped so the
# downloaded artifact validates without a network round-trip.
echo "==> Stapling"
xcrun stapler staple "$BUILT"
xcrun stapler validate "$BUILT"

rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT" "$ZIP"

echo "==> Gatekeeper assessment"
spctl --assess -vv --type install "$BUILT" 2>&1 || true

# --- Publish ----------------------------------------------------------------
echo "==> Publishing release $TAG"
gh release create "$TAG" "$ZIP" \
	--title "ASCIISaver $TAG" \
	--notes-file <(cat <<EOF
A macOS screen saver of [Time: milliseconds](https://play.ertdfgcvb.xyz/#/src/basics/time_milliseconds)
by [ertdfgcvb](https://play.ertdfgcvb.xyz), ported from
[play.core](https://github.com/ertdfgcvb/play.core).

**Install:** download \`ASCIISaver-$TAG.zip\`, unzip, double-click the \`.saver\`,
then pick *ASCIISaver* in System Settings → Screen Saver.

Signed with a Developer ID and notarized by Apple.
EOF
)

echo
echo "Released: $(gh release view "$TAG" --json url --jq .url)"
