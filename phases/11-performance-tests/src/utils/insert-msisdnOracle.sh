#!/bin/bash

## Script to insert multiple records into the oracleMSISDN table in MySQL. Shell into the mysql container, modify the script and run as needed.
set -e

# Database connection details
DB_USER="oracle_msisdn"
DB_PASS="ml_password"
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=87039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp208');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"