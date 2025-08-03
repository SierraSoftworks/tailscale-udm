#!/bin/bash

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PATH="${WORKDIR}:${PATH}"
export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"

mock "${WORKDIR}/ubnt-device-info" "1.0.0"

cat > "${WORKDIR}/tailscale" <<EOF
#!/usr/bin/env bash

# Mock the tailscale cert command
mock_tailscale_cert() {
    while [ \$# -gt 0 ]; do
        case "\$1" in
            --cert-file)
                cert_file="\$2"
                shift 2
                ;;
            --key-file)
                key_file="\$2"
                shift 2
                ;;
            *)
                #hostname="\$1"
                shift
                ;;
        esac
    done
    
    if [ -n "\$cert_file" ] && [ -n "\$key_file" ]; then
        echo "CERTIFICATE" > "\$cert_file"
        echo "PRIVATE KEY" > "\$key_file"
        return 0
    fi
    return 1
}

# Override tailscale binary variable for testing
case "\$1" in
    cert)
        shift
        mock_tailscale_cert "\$@"
        ;;
    status)
        if [ "\$2" = "--json" ]; then
            echo '{"Self": {"DNSName": "test-host.example.ts.net."}}'
        fi
        ;;
    *)
        return 0
        ;;
esac
EOF
chmod +x "${WORKDIR}/tailscale"

# Test certificate generation
test_cert_generate() {
    # Mock running state
    touch "$TAILSCALED_SOCK"
    
    # Test generate
    output=$("${ROOT}/package/manage.sh" cert generate 2>&1)
    assert_contains "$output" "Certificate generated successfully" "Output contains success message"
    assert_file_exists "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" "Certificate file exists"
    assert_file_exists "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" "Key file exists"
    
    # Check file permissions
    cert_perms=$(stat -c %a "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" 2>/dev/null || stat -f %p "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" | cut -c4-6)
    key_perms=$(stat -c %a "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" 2>/dev/null || stat -f %p "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" | cut -c4-6)
    assert_equals "644" "$cert_perms" "Certificate permissions are correct"
    assert_equals "600" "$key_perms" "Key permissions are correct"
    
    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test certificate renewal
test_cert_renew() {
    mkdir -p "$TAILSCALE_ROOT/certs"
    
    # Mock running state
    # shellcheck disable=SC2317
    _tailscale_is_running() { return 0; }
    
    # Create existing certificates
    echo "OLD CERT" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt"
    echo "OLD KEY" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key"
    
    # Test renew
    output=$("${ROOT}/package/manage.sh" cert renew 2>&1)
    assert_contains "$output" "Certificate renewed successfully" "Output contains success message"
    
    # Check that certificates were updated
    cert_content=$(cat "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt")
    assert_equals "CERTIFICATE" "$cert_content" "Certificate content is correct"
    
    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test certificate listing
test_cert_list() {
    mkdir -p "$TAILSCALE_ROOT/certs"
    
    # Create test certificates
    echo "CERT1" > "$TAILSCALE_ROOT/certs/host1.crt"
    echo "KEY1" > "$TAILSCALE_ROOT/certs/host1.key"
    echo "CERT2" > "$TAILSCALE_ROOT/certs/host2.crt"
    echo "KEY2" > "$TAILSCALE_ROOT/certs/host2.key"
    
    # Test list
    output=$("${ROOT}/package/manage.sh" cert list 2>&1)
    assert_contains "$output" "host1" "Output contains host1"
    assert_contains "$output" "host2" "Output contains host2"
    assert_contains "$output" "Certificate:" "Output contains Certificate:"
    assert_contains "$output" "Private key:" "Output contains Private key:"

    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test when tailscale is not running
test_cert_not_running() {
    mkdir -p "$TAILSCALE_ROOT"
    rm -f "$TAILSCALED_SOCK"

    # Test generate when not running
    output=$("${ROOT}/package/manage.sh" cert generate 2>&1 || true)
    assert_contains "$output" "Tailscale is not running" "Output contains not running message"
}

# Test help command
test_cert_help() {
    output=$("${ROOT}/package/manage.sh" cert help 2>&1)
    assert_contains "$output" "Usage:" "Output contains usage title"
    assert_contains "$output" "generate" "Output contains generate"
    assert_contains "$output" "renew" "Output contains renew"
    assert_contains "$output" "list" "Output contains list"
}

# Run tests
test_cert_generate
test_cert_renew
test_cert_list
test_cert_not_running
test_cert_help

echo "All certificate tests passed!"