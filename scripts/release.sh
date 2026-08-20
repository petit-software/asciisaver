#!/bin/bash
#
# Builds, signs, notarizes and publishes a GitHub release.
#
# Usage:
#   ./scripts/release.sh v1.0.0
#
# Notarization credentials — either a stored notarytool keychain profile:
#   NOTARY_PROFILE=ASCIISaver ./scripts/release.sh v1.0.0
# (create once with: xcrun notarytool store-credentials ASCIISaver \
#      --key ~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#      --key-id XXXX --issuer <issuer-uuid>)
#
# ...or the App Store Connect API key directly:
#   NOTARY_KEY=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#   NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer-uuid> ./scripts/release.sh v1.0.0
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

if ! codesign -dvv "$BUILT" 2>&1 | grep -q "Authority=Developer ID Application"; then
	echo "Not signed with a Developer ID; notarization would be rejected." >&2
	exit 1
fi
if ! codesign -d --verbose=2 "$BUILT" 2>&1 | grep -q "flags=.*runtime"; then
	echo "Hardened runtime is not enabled; notarization would be rejected." >&2
	exit 1
fi

# --- Package ----------------------------------------------------------------
echo "==> Packaging $ZIP"
mkdir -p "$DIST"
rm -f "$ZIP"
# ditto preserves the bundle's symlinks and extended attributes; `zip` does not.
ditto -c -k --keepParent "$BUILT" "$ZIP"

# --- Notarize ---------------------------------------------------------------
echo "==> Notarizing (this takes a few minutes)"
if [ -n "${NOTARY_PROFILE:-}" ]; then
	xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
	xcrun notarytool submit "$ZIP" \
		--key "$NOTARY_KEY" \
		--key-id "$NOTARY_KEY_ID" \
		--issuer "$NOTARY_ISSUER" \
		--wait
else
	echo "No notarization credentials. Set NOTARY_PROFILE, or NOTARY_KEY +" >&2
	echo "NOTARY_KEY_ID + NOTARY_ISSUER. See the header of this script." >&2
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
