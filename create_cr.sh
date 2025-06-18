#!/bin/bash

# === STEP 1: Variables ===
SN_INSTANCE="dev299595.service-now.com"
SN_USER="admin"
SN_PASS="iRN-lr6!5EnR"
LOG_FILE="./change_request.log"

# === Change Request Fields ===
ASSIGNMENT_GROUP="Software"
REASON="Automated change request for Splunk log integration using Harness CI/CD pipeline."
REQUESTED_BY="David Loo"  # Use sys_id if needed
CATEGORY="Software"
SERVICE="Splunk Platform"
SERVICE_OFFERING="Log Ingestion & Monitoring"
CONFIG_ITEM="Splunk Forwarder Node"
PRIORITY="3"
RISK="2"       # 1-Low, 2-Moderate, 3-High
IMPACT="2"     # 1-High, 2-Moderate, 3-Low

# === Planning Fields (customized for Splunk + Harness) ===
JUSTIFICATION="Integrating Splunk logging into Harness CI/CD pipeline for enhanced monitoring and automated event visibility."
IMPLEMENTATION_PLAN="1. Configure Splunk HEC endpoint\n2. Push logs from Harness CI pipeline\n3. Validate log ingestion\n4. Monitor dashboards and alerts"
RISK_ANALYSIS="There is minimal risk. If Splunk fails to receive logs, fallback logging is available locally. No impact to production flow."
BACKOUT_PLAN="Disable Splunk log stages in Harness pipeline and revert to previous logging method."
TEST_PLAN="Simulate pipeline execution and verify logs appear in Splunk index. QA will validate expected events are ingested and searchable."

echo "Creating change request..." | tee "$LOG_FILE"

# === STEP 2: Create Change Request ===
CREATE_RESPONSE=$(curl --silent --show-error -X POST \
  "https://$SN_INSTANCE/api/now/table/change_request" \
  -u "$SN_USER:$SN_PASS" \
  -H "Content-Type: application/json" \
  -d "{
        \"short_description\": \"Splunk Log Integration via Harness Pipeline\",
        \"description\": \"$REASON\",
        \"category\": \"$CATEGORY\",
        \"priority\": \"$PRIORITY\",
        \"risk\": \"$RISK\",
        \"impact\": \"$IMPACT\",
        \"assignment_group\": \"$ASSIGNMENT_GROUP\",
        \"cmdb_ci\": \"$CONFIG_ITEM\",
        \"service\": \"$SERVICE\",
        \"service_offering\": \"$SERVICE_OFFERING\",
        \"justification\": \"$JUSTIFICATION\",
        \"implementation_plan\": \"$IMPLEMENTATION_PLAN\",
        \"risk_and_impact_analysis\": \"$RISK_ANALYSIS\",
        \"backout_plan\": \"$BACKOUT_PLAN\",
        \"test_plan\": \"$TEST_PLAN\",
        \"state\": \"Assess\"
      }")

echo "Response: $CREATE_RESPONSE" | tee -a "$LOG_FILE"

# === STEP 3: Extract sys_id and number ===
CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/"sys_id":"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/"number":"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 4: Poll for Implement or Rejected state ===
echo "⏳ Waiting for Change Request to be Approved and enter 'Implement' state..." | tee -a "$LOG_FILE"

MAX_RETRIES=30
SLEEP_INTERVAL=30
COUNT=0
LAST_STATE=""
LAST_APPROVAL=""

while [ $COUNT -lt $MAX_RETRIES ]; do
  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  # Extract state and approval status
  CHANGE_STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/"state":"//')
  APPROVAL_STATUS=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/"approval":"//')

  if [[ "$CHANGE_STATE" != "$LAST_STATE" || "$APPROVAL_STATUS" != "$LAST_APPROVAL" ]]; then
    echo "[$(date)] State: $CHANGE_STATE | Approval: $APPROVAL_STATUS" | tee -a "$LOG_FILE"
    LAST_STATE=$CHANGE_STATE
    LAST_APPROVAL=$APPROVAL_STATUS
  fi

  if [[ "$CHANGE_STATE" == "-1" || "$APPROVAL_STATUS" == "approved" ]]; then
    echo "✅ Change Request is approved and in 'Implement' state. Continuing pipeline..." | tee -a "$LOG_FILE"
    exit 0
  elif [[ "$APPROVAL_STATUS" == "rejected" || "$CHANGE_STATE" == "8" ]]; then
    echo "❌ Change Request was Rejected. Aborting pipeline." | tee -a "$LOG_FILE"
    exit 1
  fi

  COUNT=$((COUNT+1))
  echo "Waiting... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout waiting for 'Implement' state or approval." | tee -a "$LOG_FILE"
exit 1
