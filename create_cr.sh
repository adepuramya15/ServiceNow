#!/bin/bash

# === STEP 1: Ask user to proceed ===
while true; do
  read -p "Do you want to raise a Change Request? (yes/no): " USER_INPUT
  case "$USER_INPUT" in
    yes ) break ;;
    no ) echo "❌ Change Request creation aborted by user."; exit 0 ;;
    * ) echo "Please answer yes or no." ;;
  esac
done

# === STEP 2: Variables ===
SN_INSTANCE="dev214721.service-now.com"
SN_USER="admin"
SN_PASS="+zL%FlUb87Un"
LOG_FILE="./change_request.log"
ASSIGNMENT_GROUP="287ebd7da9fe198100f92cc8d1d2154e"

echo "Creating change request..." | tee "$LOG_FILE"

# === STEP 3: Create Change Request ===
CREATE_RESPONSE=$(curl --silent --show-error -X POST \
  "https://$SN_INSTANCE/api/now/table/change_request" \
  -u "$SN_USER:$SN_PASS" \
  -H "Content-Type: application/json" \
  -d "{
        \"short_description\": \"Automated Change Request from Harness CI Pipeline\",
        \"description\": \"Triggered by deployment pipeline.\",
        \"category\": \"Software\",
        \"priority\": \"3\",
        \"assignment_group\": \"$ASSIGNMENT_GROUP\",
        \"state\": \"Assess\"
      }")

echo "Response: $CREATE_RESPONSE" | tee -a "$LOG_FILE"

# === STEP 4: Extract sys_id and change number ===
CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/"sys_id":"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/"number":"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 5: Poll for Implement state ===
echo "⏳ Waiting for Change Request to enter 'Implement' state..." | tee -a "$LOG_FILE"

MAX_RETRIES=30
SLEEP_INTERVAL=30
COUNT=0
LAST_STATE=""

while [ $COUNT -lt $MAX_RETRIES ]; do
  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  CHANGE_STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/"state":"//')

  if [[ "$CHANGE_STATE" != "$LAST_STATE" ]]; then
    echo "[$(date)] Change Request State: $CHANGE_STATE" | tee -a "$LOG_FILE"
    LAST_STATE=$CHANGE_STATE
  fi

  if [[ "$CHANGE_STATE" == "-1" ]]; then
    echo "✅ Change Request is in 'Implement' state. Continuing pipeline..." | tee -a "$LOG_FILE"
    exit 0
  fi

  COUNT=$((COUNT+1))
  echo "Waiting... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout waiting for 'Implement' state." | tee -a "$LOG_FILE"
exit 1
