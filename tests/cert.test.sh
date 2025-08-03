#!/bin/bash

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PATH="${WORKDIR}:${PATH}"
export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"

mock "${WORKDIR}/ubnt-device-info" "2.0.0"
touch "${TAILSCALED_SOCK}"  # Create the tailscaled socket for testing

# systemctl mock, used to ensure the installer doesn't block thinking that tailscale is running
cat > "${WORKDIR}/systemctl" <<EOF
#!/usr/bin/env bash

case "\$1" in
    "is-active")
        if [ ! -f "${WORKDIR}/tailscaled.sock" ]; then
            exit 1
        fi
        ;;
    *)
        echo "Unexpected command: \${1}"
        exit 1
        ;;
esac
EOF
chmod +x "${WORKDIR}/systemctl"

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
    touch "$TAILSCALED_SOCK"  # Mock running state
    
    # Test generate
    output=$("${ROOT}/package/manage.sh" cert generate 2>&1)
    assert_contains "$output" "Certificate generated successfully" "Output contains success message"
    assert_file_exists "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" "Certificate file exists"
    assert_file_exists "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" "Key file exists"

    # Check file permissions
    cert_perms=$(stat -c %a "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" 2>/dev/null || stat -f %p "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt" | cut -c4-6)
    key_perms=$(stat -c %a "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" 2>/dev/null || stat -f %p "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key" | cut -c4-6)
    assert_eq "644" "$cert_perms" "Certificate permissions are correct"
    assert_eq "600" "$key_perms" "Key permissions are correct"

    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test certificate renewal
test_cert_renew() {
    mkdir -p "$TAILSCALE_ROOT/certs"
    touch "$TAILSCALED_SOCK"  # Mock running state
    
    # Create existing certificates
    echo "OLD CERT" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt"
    echo "OLD KEY" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key"
    
    # Test renew
    output=$("${ROOT}/package/manage.sh" cert renew 2>&1)
    assert_contains "$output" "Certificate renewed successfully" "Output contains success message"

    # Check that certificates were updated
    cert_content=$(cat "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt")
    assert_eq "CERTIFICATE" "$cert_content" "Certificate content is correct"

    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test certificate listing
test_cert_info() {
    mkdir -p "$TAILSCALE_ROOT/certs"
    
    # Create test certificates
    echo "CERT" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.crt"
    echo "KEY" > "$TAILSCALE_ROOT/certs/test-host.example.ts.net.key"

    # Test list
    output=$("${ROOT}/package/manage.sh" cert info 2>&1)
    assert_contains "$output" "Certificate:" "Output contains Certificate path"
    assert_contains "$output" "test-host.example.ts.net.crt" "Output contains test-host.example.ts.net.crt"
    assert_contains "$output" "Private key:" "Output contains Private key path"
    assert_contains "$output" "test-host.example.ts.net.key" "Output contains test-host.example.ts.net.key"

    rm -rf "$TAILSCALE_ROOT/certs"
}

# Test when tailscale is not running
test_cert_not_running() {
    mkdir -p "$TAILSCALE_ROOT"
    
    # Mock not running state
    rm -f "$TAILSCALED_SOCK"

    # Test generate when not running
    output=$("${ROOT}/package/manage.sh" cert generate 2>&1 || true)
    assert_contains "$output" "Tailscale is not running" "Output contains not running message"
}

# Test help command
test_cert_help() {
    output=$("${ROOT}/package/manage.sh" cert help 2>&1)
    assert_contains "$output" "Usage:" "Output contains usage title"
    assert_contains "$output" "generate" "Output contains generate command"
    assert_contains "$output" "renew" "Output contains renew command"
    assert_contains "$output" "info" "Output contains info command"
    assert_contains "$output" "install-unifi" "Output contains install-unifi command"
}

# Run tests
test_cert_generate
test_cert_renew
test_cert_info
test_cert_not_running
test_cert_help

echo "All certificate tests passed!"