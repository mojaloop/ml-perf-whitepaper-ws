#!/bin/sh

## Script to register MSISDNs on Simulator backend. Modify and run as needed.

# Base URL and headers
URL="http://sim-fsp202.local/sim/fsp202/test/repository/parties"
FSP_SOURCE="fsp201"
CONTENT_TYPE="application/json"
ACCEPT_ENCODING="gzip, compress, deflate, br"

# Starting ID and count
START_ID=17039811929
COUNT=1000

# JSON payload template (excluding idValue and lastName)
JSON_BASE='{"displayName":"Test FSP","firstName":"Test","middleName":"Test","lastName":"FSP'

# Initialize counter
i=0
while [ $i -lt $COUNT ]
do
    CURRENT_ID=`expr $START_ID + $i`
    JSON_PAYLOAD="${JSON_BASE}${CURRENT_ID}\",\"dateOfBirth\":\"1984-01-01\",\"idType\":\"MSISDN\",\"idValue\":\"${CURRENT_ID}\"}"
    
    curl "$URL" \
        -H "fspiop-source: $FSP_SOURCE" \
        -H "content-type: $CONTENT_TYPE" \
        -H "accept-encoding: $ACCEPT_ENCODING" \
        --data-binary "$JSON_PAYLOAD" \
        --compressed
    
    # Check if curl command was successful
    if [ $? -eq 0 ]; then
        echo "Successfully sent request for idValue: $CURRENT_ID"
    else
        echo "Error sending request for idValue: $CURRENT_ID"
    fi

    # Increment counter
    i=`expr $i + 1`
done

echo "Completed sending $COUNT curl requests"