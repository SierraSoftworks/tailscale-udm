#!/bin/bash

# arguments: cert_uuid crt_file key_file hostname
CERT_UUID=$1
CRT_FILE=$2
KEY_FILE=$3
HOSTNAME=$4

# postgresql connection info
PG_USER="unifi-core"
PG_DB="unifi-core"
PG_HOST="localhost"
PG_PORT="5432"

# read cert and key files
CERT_DATA=$(cat "$CRT_FILE" | sed "s/'/''/g")
KEY_DATA=$(cat "$KEY_FILE" | sed "s/'/''/g")

# extract subject as JSON string (escaped)
SUBJECT=$(openssl x509 -in "$CRT_FILE" -noout -subject -nameopt RFC2253 | sed 's/subject= //' | awk -F',' '
{
  printf("{");
  for(i=1;i<=NF;i++)
    printf("\"%s\": [\"%s\"]%s", $i, $i, (i==NF ? "" : ","));
  printf("}");
}' | sed "s/'/''/g")

# extract valid from and valid to
VALID_FROM=$(openssl x509 -in "$CRT_FILE" -noout -startdate | sed 's/notBefore=//')
VALID_TO=$(openssl x509 -in "$CRT_FILE" -noout -enddate | sed 's/notAfter=//')

# convert dates to ISO 8601
VALID_FROM_ISO=$(date -d "$VALID_FROM" --iso-8601=seconds)
VALID_TO_ISO=$(date -d "$VALID_TO" --iso-8601=seconds)

# serial number
SERIAL=$(openssl x509 -in "$CRT_FILE" -noout -serial | sed 's/serial=//')

# fingerprint sha1
FINGERPRINT=$(openssl x509 -in "$CRT_FILE" -noout -fingerprint | sed 's/SHA1 Fingerprint=//')

# issuer JSON string
ISSUER=$(openssl x509 -in "$CRT_FILE" -noout -issuer -nameopt RFC2253 | sed 's/issuer= //' | awk -F',' '
{
  printf("{");
  for(i=1;i<=NF;i++)
    printf("\"%s\": [\"%s\"]%s", $i, $i, (i==NF ? "" : ","));
  printf("}");
}' | sed "s/'/''/g")

# subject alternative names in JSON
SAN_RAW=$(openssl x509 -in "$CRT_FILE" -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed 's/ //g')
dns=""
ip=""
for i in $(echo "$SAN_RAW" | sed 's/,/ /g'); do
    case "$i" in
        DNS:*) dns="${dns}${dns:+,}\"$(echo "$i" | sed 's/DNS://')\"" ;;
        IPAddress:*) ip="${ip}${ip:+,}\"$(echo "$i" | sed 's/IPAddress://')\"" ;;
    esac
done
SAN_JSON="{"
if [ -n "$dns" ]; then
    SAN_JSON="$SAN_JSON\"DNS\":[$dns]"
fi
if [ -n "$ip" ]; then
    if [ -n "$dns" ]; then
        SAN_JSON="$SAN_JSON,"
    fi
    SAN_JSON="$SAN_JSON\"IP Address\":[$ip]"
fi
SAN_JSON="$SAN_JSON}"

# version placeholder
VERSION=1

# check if there's already a cert with this subject
EXIST=$(psql -U "$PG_USER" -d "$PG_DB" -h "$PG_HOST" -p "$PG_PORT" -tAc "SELECT 1 FROM user_certificates WHERE subject::jsonb @> '$SUBJECT'::jsonb")

if [ "$EXIST" = "1" ]; then
    # delete existing matching cert
    psql -U "$PG_USER" -d "$PG_DB" -h "$PG_HOST" -p "$PG_PORT" -c "DELETE FROM user_certificates WHERE subject::jsonb @> '$SUBJECT'::jsonb;"
fi

# insert new certificate record
psql -U "$PG_USER" -d "$PG_DB" -h "$PG_HOST" -p "$PG_PORT" <<EOF
INSERT INTO user_certificates
    (id, name, key, cert, version, fingerprint, serial_number, subject, issuer, subject_alt_name, valid_from, valid_to)
VALUES
    ('$CERT_UUID', '$HOSTNAME', '$KEY_DATA', '$CERT_DATA', $VERSION, '$FINGERPRINT', '$SERIAL', '$SUBJECT', json('$ISSUER'), '$SAN_JSON', '$VALID_FROM_ISO', '$VALID_TO_ISO');
EOF

echo "Inserted/updated certificate with id $CERT_UUID and name $HOSTNAME into database."
