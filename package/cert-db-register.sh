#!/bin/bash
# Register certificate in UniFi OS PostgreSQL database

cert_uuid="$1"
cert_file="$2"
key_file="$3"
hostname="${4:-$(hostname)}"

if [ -z "$cert_uuid" ] || [ -z "$cert_file" ] || [ -z "$key_file" ]; then
    echo "Usage: $0 <uuid> <cert_file> <key_file> [hostname]"
    exit 1
fi

# Read certificate content and escape for PostgreSQL
cert_content=$(sed "s/'/\'\'/g" "$cert_file")
key_content=$(sed "s/'/\'\'/g" "$key_file")

# Extract certificate details using openssl
if command -v openssl >/dev/null 2>&1; then
    # Get certificate dates
    not_before=$(openssl x509 -noout -startdate -in "$cert_file" | cut -d= -f2)
    not_after=$(openssl x509 -noout -enddate -in "$cert_file" | cut -d= -f2)
    
    # Convert to timestamps
    if date --version >/dev/null 2>&1; then
        # GNU date
        valid_from=$(date -d "$not_before" --iso-8601=seconds)
        valid_to=$(date -d "$not_after" --iso-8601=seconds)
    else
        # BSD date (macOS)
        valid_from=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_before" "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date --iso-8601=seconds)
        valid_to=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date -d "+90 days" --iso-8601=seconds)
    fi
    
    # Get certificate details
    subject_text=$(openssl x509 -noout -subject -in "$cert_file" | sed 's/subject=//')
    #issuer_text=$(openssl x509 -noout -issuer -in "$cert_file" | sed 's/issuer=//')
    serial=$(openssl x509 -noout -serial -in "$cert_file" | cut -d= -f2)
    fingerprint=$(openssl x509 -noout -fingerprint -SHA256 -in "$cert_file" | cut -d= -f2 | tr -d ':')
    
    # Extract CN from subject
    cn=$(echo "$subject_text" | grep -o 'CN = [^,]*' | sed 's/CN = //' || echo "$hostname")
    
    # Get version (usually 3 for v3 certificates)
    version=$(openssl x509 -noout -text -in "$cert_file" | grep "Version:" | grep -o '[0-9]' | head -1 || echo "3")
else
    # Fallback values if openssl is not available
    valid_from=$(date --iso-8601=seconds)
    valid_to=$(date -d "+90 days" --iso-8601=seconds)
    cn="$hostname"
    serial="0"
    fingerprint="0"
    version="3"
fi

# Escape values for SQL
cn_escaped="${cn//\'/\'\'}"  # Escape single quotes
cert_name="Tailscale Certificate - $cn_escaped"

# PostgreSQL connection settings
PGHOST="/run/postgresql"
PGPORT="5432"
PGDATABASE="unifi-core"
PGUSER="unifi-core"

# Create the SQL command
SQL_CMD="INSERT INTO user_certificates (
    id,
    name,
    cert,
    key,
    version,
    serial_number,
    fingerprint,
    subject,
    issuer,
    subject_alt_name,
    valid_from,
    valid_to,
    created_at,
    updated_at
) VALUES (
    '$cert_uuid'::uuid,
    '$cert_name',
    E'$cert_content',
    E'$key_content',
    $version,
    '$serial',
    '$fingerprint',
    '{\"CN\": \"$cn_escaped\"}'::jsonb,
    '{\"CN\": \"Let''s Encrypt\", \"O\": \"Let''s Encrypt\", \"C\": \"US\"}'::jsonb,
    '[\"$cn_escaped\"]'::jsonb,
    '$valid_from'::timestamp with time zone,
    '$valid_to'::timestamp with time zone,
    NOW(),
    NOW()
) ON CONFLICT (id) DO UPDATE SET
    cert = EXCLUDED.cert,
    key = EXCLUDED.key,
    version = EXCLUDED.version,
    serial_number = EXCLUDED.serial_number,
    fingerprint = EXCLUDED.fingerprint,
    subject = EXCLUDED.subject,
    issuer = EXCLUDED.issuer,
    subject_alt_name = EXCLUDED.subject_alt_name,
    valid_from = EXCLUDED.valid_from,
    valid_to = EXCLUDED.valid_to,
    updated_at = NOW();"

# Execute the SQL
if command -v psql >/dev/null 2>&1; then
    echo "$SQL_CMD" | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE"
    result=$?
else
    # Try to use UniFi's psql if available
    if [ -x "/usr/lib/unifi/bin/psql" ]; then
        echo "$SQL_CMD" | /usr/lib/unifi/bin/psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE"
        result=$?
    else
        echo "PostgreSQL client not found. Cannot register certificate in database."
        exit 1
    fi
fi

if [ $result -eq 0 ]; then
    echo "Certificate registered in database with UUID: $cert_uuid"
else
    echo "Failed to register certificate in database"
    exit 1
fi