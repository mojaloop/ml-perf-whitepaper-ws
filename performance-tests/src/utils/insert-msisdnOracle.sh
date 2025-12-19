#!/usr/bin/env bash

## Script to insert multiple records into the oracleMSISDN table in MySQL.
## Copy into the mysqldb pod and run as needed.

set -euo pipefail

# Database connection details
DB_USER="root"
DB_PASS="${MYSQL_ROOT_PASSWORD:-}"
DB_NAME="oracle_msisdn"

if [[ -z "$DB_PASS" ]]; then
  echo "ERROR: MYSQL_ROOT_PASSWORD environment variable is not set." >&2
  exit 1
fi

# Number of records to insert per FSP
COUNT=1000

# List of FSPs and their starting IDs (fspId:startId)
FSP_CONFIGS=(
  "fsp202:17039811929"
  "fsp203:37039811929"
  "fsp204:47039811929"
  "fsp205:57039811929"
  "fsp206:67039811929"
  "fsp207:77039811929"
  "fsp208:87039811929"
)

for cfg in "${FSP_CONFIGS[@]}"; do
  IFS=':' read -r FSP_ID START_ID <<< "$cfg"

  echo "Inserting $COUNT rows for ${FSP_ID} starting at ${START_ID}..."

  # Build a single SQL batch wrapped in a transaction
  SQL="START TRANSACTION;"
  for ((i=0; i<COUNT; i++)); do
    CURRENT_ID=$((START_ID + i))
    SQL+="INSERT INTO oracleMSISDN (id, fspId) VALUES (${CURRENT_ID}, '${FSP_ID}');"
  done
  SQL+="COMMIT;"

  # Execute the batch
  if mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"; then
    echo "Completed inserting $COUNT records for ${FSP_ID}"
  else
    echo "Error inserting records for ${FSP_ID}" >&2
    exit 1
  fi
done

echo "All inserts completed."
