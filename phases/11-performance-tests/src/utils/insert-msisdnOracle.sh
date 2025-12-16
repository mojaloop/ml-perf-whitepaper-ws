#!/bin/bash

## Script to insert multiple records into the oracleMSISDN table in MySQL. Shell into the mysql container, modify the script and run as needed.
set -e

# insert into oracleMSISDN(id, fspId) values(17039811918, 'fsp201');
# insert into oracleMSISDN(id, fspId) values(17039811919, 'fsp202');
# insert into oracleMSISDN(id, fspId) values(17039811920, 'fsp203');
# insert into oracleMSISDN(id, fspId) values(17039811921, 'fsp204');
# insert into oracleMSISDN(id, fspId) values(17039811922, 'fsp205');
# insert into oracleMSISDN(id, fspId) values(17039811923, 'fsp206');
# insert into oracleMSISDN(id, fspId) values(17039811924, 'fsp207');
# insert into oracleMSISDN(id, fspId) values(17039811925, 'fsp208');

# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=17039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp202');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"


# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=37039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp203');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"

# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=47039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp204');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"

# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=57039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp205');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"


# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=67039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp206');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"


# Database connection details
DB_USER="root"
DB_PASS=""
DB_NAME="oracle_msisdn"

# Starting ID
START_ID=77039811929
# Number of records to insert
COUNT=1000

# Loop to generate and execute INSERT statements
for ((i=0; i<COUNT; i++))
do
    CURRENT_ID=$((START_ID + i))
    SQL="INSERT INTO oracleMSISDN (id, fspId) VALUES ($CURRENT_ID, 'fsp207');"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$SQL"
    
    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "Inserted ID: $CURRENT_ID"
    else
        echo "Error inserting ID: $CURRENT_ID"
    fi
done

echo "Completed inserting $COUNT records"



# Database connection details
DB_USER="root"
DB_PASS=""
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