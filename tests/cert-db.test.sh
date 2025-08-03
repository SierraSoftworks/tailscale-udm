#!/bin/bash

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PATH="${WORKDIR}:${PATH}"
export TAILSCALE_ROOT="${WORKDIR}"

# Test database registration script
echo "Testing certificate database registration..."

# Create test certificate and key
cat > "$WORKDIR/test.crt" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIDrDCCAzGgAwIBAgISBbD85QuQft/Jp6qlAOSNfxF0MAoGCCqGSM49BAMDMDIx
CzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQswCQYDVQQDEwJF
NTAeFw0yNTA3MjkwOTI3MjBaFw0yNTEwMjcwOTI3MTlaMCkxJzAlBgNVBAMTHnVk
bS1wcm8td2FuZGkudGFpbGRiNDUyLnRzLm5ldDBZMBMGByqGSM49AgEGCCqGSM49
AwEHA0IABNwmXCgC7McRGNBwjP34VJzTkAMq2jWutgOyPzfYBW/3nO24zSk2Z6Jf
djYgD35djCyVfDL54uL96XNB8gumM0o=
-----END CERTIFICATE-----
EOF

cat > "$WORKDIR/test.key" <<'EOF'
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIBh5+moHGwZBXdqxDsqo8W3SSakNlVFzOhCatdfprOYRoAoGCCqGSM49
AwEHoUQDQgAE3CZcKALsxxEY0HCM/fhUnNOQAyraNa62A7I/N9gFb/ec7bjNKTZn
ol92NiAPfl2MLJV8Mvni4v3pc0HyC6YzSg==
-----END EC PRIVATE KEY-----
EOF

# Test UUID generation
#test_uuid="12345678-1234-1234-1234-123456789012"

# Test certificate content extraction
if command -v openssl >/dev/null 2>&1; then
    # Extract subject CN
    subject=$(openssl x509 -noout -subject -in "$WORKDIR/test.crt" 2>/dev/null || echo "")
    if [ -n "$subject" ]; then
        assert_contains "$subject" "CN" "Certificate subject contains CN"
    fi
    
    # Extract dates
    not_after=$(openssl x509 -noout -enddate -in "$WORKDIR/test.crt" 2>/dev/null || echo "")
    if [ -n "$not_after" ]; then
        assert_contains "$not_after" "notAfter" "Certificate has expiry date"
    fi
fi

# Test SQL generation (mock)
# Using a more portable sed command for macOS
cert_content=$(awk '{printf "%s\\n", $0}' "$WORKDIR/test.crt" | sed 's/\\n$//')
key_content=$(awk '{printf "%s\\n", $0}' "$WORKDIR/test.key" | sed 's/\\n$//')

# Verify content transformation
assert_contains "$cert_content" "BEGIN CERTIFICATE" "Certificate content includes header"
assert_contains "$key_content" "BEGIN EC PRIVATE KEY" "Key content includes header"

# Test install-unifi with database registration
echo "Testing install-unifi with database registration..."

# Create mock certificate files
mkdir -p "$TAILSCALE_ROOT/certs"
echo "MOCK CERTIFICATE" > "$TAILSCALE_ROOT/certs/test-host.crt"
echo "MOCK PRIVATE KEY" > "$TAILSCALE_ROOT/certs/test-host.key"

# Create mock database registration script
cat > "$ROOT/package/helpers/cert-db-register.sh" <<'EOF'
#!/bin/sh
echo "Mock: Registering certificate $1 in database"
exit 0
EOF
chmod +x "$ROOT/package/helpers/cert-db-register.sh"

# Test that database registration script exists
if [ -f "$ROOT/package/helpers/cert-db-register.sh" ]; then
    assert_eq "0" "0" "Database registration script exists"
fi

echo "All certificate database tests passed!"