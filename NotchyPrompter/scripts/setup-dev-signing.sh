#!/usr/bin/env bash
#
# setup-dev-signing.sh — one-time creation of a stable self-signed code-
# signing identity for NotchyPrompter local development.
#
# Why this exists:
#   build.sh used to ad-hoc sign (codesign --sign -). Ad-hoc signatures
#   produce a different cdhash on every build, so macOS TCC treats each
#   rebuild as a brand-new app identity and revokes Screen Recording
#   permission. Signing with a stable self-signed certificate gives the
#   binary a Designated Requirement that includes the leaf-cert SHA, so
#   TCC keeps the grant across rebuilds.
#
# What this script does:
#   1. Idempotent check — exits 0 if a "NotchyPrompter Dev" identity is
#      already usable by codesign.
#   2. Generates an RSA key + self-signed X.509 cert with the codeSigning
#      Extended Key Usage (OID 1.3.6.1.5.5.7.3.3) using openssl.
#   3. Imports the resulting PKCS#12 bundle into the login keychain with
#      -T /usr/bin/codesign so codesign is on the ACL.
#   4. Calls security set-key-partition-list (apple-tool:,apple:) so
#      codesign can use the private key non-interactively. Without this
#      step macOS prompts for the keychain password on every codesign
#      invocation, even with -T set — this is rdar://28524119 / a known
#      Sierra+ behaviour change.
#   5. Adds the certificate to the login keychain's trust store so
#      codesign accepts it as valid.
#
# Usage:
#   NotchyPrompter/scripts/setup-dev-signing.sh
#
# Notes:
#   - Requires the user's login keychain password once (prompted via
#     `security` if needed). Cannot avoid this — set-key-partition-list
#     requires the keychain password by design.
#   - Safe to re-run; the idempotent guard skips work when the identity
#     already exists.

set -euo pipefail

CERT_CN="NotchyPrompter Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TMPDIR_ROOT="$(mktemp -d -t notchy-signing)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

KEY_PATH="${TMPDIR_ROOT}/key.pem"
CERT_PATH="${TMPDIR_ROOT}/cert.pem"
P12_PATH="${TMPDIR_ROOT}/identity.p12"
OPENSSL_CONF="${TMPDIR_ROOT}/openssl.cnf"
P12_PASS="notchyprompter-dev-transient"

log() { printf '==> %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Idempotent guard.
# ---------------------------------------------------------------------------
# `security find-identity -v -p codesigning` lists identities valid for
# codesigning. If "NotchyPrompter Dev" is already present, we're done.
if security find-identity -v -p codesigning | grep -q "\"${CERT_CN}\""; then
    log "Code-signing identity \"${CERT_CN}\" already present — nothing to do."
    log "If codesign still prompts for a password, re-run this script to"
    log "refresh the partition list."
    exit 0
fi

log "No existing \"${CERT_CN}\" identity — creating one."

# ---------------------------------------------------------------------------
# 2. Generate the key and self-signed cert with openssl.
# ---------------------------------------------------------------------------
# We need:
#   - RSA 2048 (codesign accepts it; ECDSA also works but RSA is simplest)
#   - basicConstraints CA:FALSE (leaf cert)
#   - keyUsage digitalSignature (required by codesign)
#   - extendedKeyUsage codeSigning (1.3.6.1.5.5.7.3.3) — without this the
#     identity won't show up under `find-identity -p codesigning`.
cat > "$OPENSSL_CONF" <<'EOF'
[ req ]
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_codesign

[ req_dn ]
CN = NotchyPrompter Dev

[ v3_codesign ]
basicConstraints     = critical, CA:FALSE
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
subjectKeyIdentifier = hash
EOF

log "Generating RSA key + self-signed cert (10 years)"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" \
    -days 3650 \
    -config "$OPENSSL_CONF" \
    -extensions v3_codesign >/dev/null 2>&1

log "Bundling key + cert into PKCS#12 for keychain import"
openssl pkcs12 -export \
    -inkey "$KEY_PATH" \
    -in "$CERT_PATH" \
    -name "$CERT_CN" \
    -out "$P12_PATH" \
    -passout "pass:${P12_PASS}" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 3. Import into the login keychain.
# ---------------------------------------------------------------------------
# -T /usr/bin/codesign whitelists codesign on the key's ACL. This is
# necessary but NOT sufficient on Sierra+ — see step 4.
log "Importing identity into login keychain"
security import "$P12_PATH" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null

# ---------------------------------------------------------------------------
# 4. Allow codesign to use the private key non-interactively.
# ---------------------------------------------------------------------------
# Sierra introduced a partition list ACL on top of the per-app ACL. Without
# this step, codesign triggers a "allow / always allow" GUI prompt every
# time, even with -T set during import. apple-tool:,apple: covers the
# Apple-shipped tooling (codesign, security, productsign, etc.).
#
# This step requires the login keychain password. We invoke `security`
# without -k so it prompts the user once via the standard CLI prompt
# (no GUI). If the user has SecurityAgent caching, even that prompt may
# be suppressed.
log "Granting codesign non-interactive access to the private key"
log "(you may be prompted for your login keychain password once)"
if ! security set-key-partition-list \
        -S "apple-tool:,apple:" \
        -s \
        -D "$CERT_CN" \
        -t private \
        "$KEYCHAIN" >/dev/null; then
    err "set-key-partition-list failed."
    err "If you skipped the password prompt, re-run this script and enter"
    err "your login keychain password when prompted."
    exit 1
fi

# ---------------------------------------------------------------------------
# 5. Trust the cert for codesigning.
# ---------------------------------------------------------------------------
# Without an explicit trust setting, codesign will refuse with
# "errSecCSReqFailed" because the leaf chains to no trusted root.
# add-trusted-cert with -p codeSign tells the system to trust this leaf
# specifically for code signing.
#
# Note: -d (admin trust, system-wide) requires sudo. We use the user
# trust settings (no -d) so the script doesn't need root. This is
# sufficient for local development.
log "Marking certificate as trusted for code signing (user trust)"
if ! security add-trusted-cert \
        -p codeSign \
        -k "$KEYCHAIN" \
        "$CERT_PATH" >/dev/null 2>&1; then
    err "add-trusted-cert failed. The identity exists but codesign may"
    err "report 'CSSMERR_TP_NOT_TRUSTED'. You can grant trust manually:"
    err "  open the cert in Keychain Access → Trust → Code Signing → Always Trust"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verification.
# ---------------------------------------------------------------------------
if ! security find-identity -v -p codesigning | grep -q "\"${CERT_CN}\""; then
    err "Identity was created but does not appear in"
    err "  security find-identity -v -p codesigning"
    err "Something went wrong; please report this."
    exit 1
fi

log "Done."
echo
echo "  Identity: ${CERT_CN}"
echo "  Keychain: ${KEYCHAIN}"
echo
echo "Next: cd NotchyPrompter && ./build.sh"
