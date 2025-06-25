#!/bin/bash

# === STEP 1: Variables ===
SN_INSTANCE="dev299595.service-now.com"
SN_USER="admin"
SN_PASS="iRN-lr6!5EnR"
LOG_FILE="./change_request.log"

# === Change Request Fields ===
ASSIGNMENT_GROUP="Software"
REASON="Automated change request for Splunk log integration using Harness CI/CD pipeline."
REQUESTED_BY="David Loo"
CATEGORY="Software"
BUSINESS_SERVICE="IT Services"
SERVICE_OFFERING="Log Ingestion & Monitoring"
CONFIG_ITEM="IT Services"
PRIORITY="3"
RISK="2"
IMPACT="2"
ASSIGNED_TO_SYS_ID="ed36e12b9782a61077bf3fdce053af01"

# === Planning Fields ===
JUSTIFICATION="Integrating Splunk logging into Harness CI/CD pipeline for enhanced monitoring and automated event visibility."
IMPLEMENTATION_PLAN="1. Configure Splunk HEC endpoint\n2. Push logs from Harness CI pipeline\n3. Validate log ingestion\n4. Monitor dashboards and alerts"
RISK_AND_IMPACT_ANALYSIS="Risk is minimal. If Splunk fails to receive logs, fallback logging remains active on Jenkins and Harness. No disruption expected."
BACKOUT_PLAN="Revert to default Jenkins logging by disabling Splunk steps in the pipeline."
TEST_PLAN="Trigger CI/CD job, verify that logs are received in Splunk index, and validate using search query."

CAB_REQUIRED="true"
CAB_DELEGATE="Change Advisory Board"
CAB_RECOMMENDATION="Approved - Proceed with minimal risk"

# === STEP 2: Create CR ===
echo "📦 Creating change request..." | tee "$LOG_FILE"
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
    \"assigned_to\": \"$ASSIGNED_TO_SYS_ID\"
  }")

SYS_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/"sys_id":"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/"number":"//')

if [ -z "$SYS_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  echo "$CREATE_RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $SYS_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 3: Update Planning Fields ===
echo "🔄 Updating planning fields..." | tee -a "$LOG_FILE"
curl --silent --request PATCH \
  "https://$SN_INSTANCE/api/now/table/change_request/$SYS_ID" \
  --user "$SN_USER:$SN_PASS" \
  --header "Content-Type: application/json" \
  --data "{
    \"cmdb_ci\": \"$CONFIG_ITEM\",
    \"business_service\": \"$BUSINESS_SERVICE\",
    \"service_offering\": \"$SERVICE_OFFERING\",
    \"justification\": \"$JUSTIFICATION\",
    \"implementation_plan\": \"$IMPLEMENTATION_PLAN\",
    \"risk_and_impact_analysis\": \"$RISK_AND_IMPACT_ANALYSIS\",
    \"backout_plan\": \"$BACKOUT_PLAN\",
    \"test_plan\": \"$TEST_PLAN\",
    \"cab_required\": \"$CAB_REQUIRED\",
    \"cab_delegate\": \"$CAB_DELEGATE\",
    \"cab_recommendation\": \"$CAB_RECOMMENDATION\",
    \"state\": \"Assess\"
  }" > /dev/null

# === STEP 4: Monitor Change Request Progress ===
SCHEDULED_SET=false
WAITED_FOR_START=false
MAX_RETRIES=60
SLEEP_INTERVAL=30
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
  POLL_RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$SYS_ID")

  CHANGE_STATE=$(echo "$POLL_RESPONSE" | grep -o '"state":"[^"]*' | cut -d':' -f2 | tr -d '"')
  APPROVAL=$(echo "$POLL_RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/"approval":"//')

  echo "🔄 Current State: $CHANGE_STATE | Approval: $APPROVAL" | tee -a "$LOG_FILE"

  if [[ "$APPROVAL" == "rejected" ]]; then
    echo "❌ Change Request Rejected. Exiting." | tee -a "$LOG_FILE"
    exit 1
  fi

  if [[ "$CHANGE_STATE" == "-2" && "$SCHEDULED_SET" == "false" ]]; then
    # Initial schedule setup
    UTC_START=$(date -u -d "+3 minutes" +"%Y-%m-%d %H:%M:%S")
    UTC_END=$(date -u -d "+35 minutes" +"%Y-%m-%d %H:%M:%S")

    curl --silent --user "$SN_USER:$SN_PASS" -X PATCH \
      "https://$SN_INSTANCE/api/now/table/change_request/$SYS_ID" \
      -H "Content-Type: application/json" \
      -d "{
            \"start_date\": \"$UTC_START\",
            \"end_date\": \"$UTC_END\"
          }" > /dev/null

    echo "🕒 Scheduled Start (UTC): $UTC_START" | tee -a "$LOG_FILE"
    echo "🕒 Scheduled End   (UTC): $UTC_END" | tee -a "$LOG_FILE"

    SCHEDULED_SET=true
    WAITED_FOR_START=true
  fi

  if [[ "$CHANGE_STATE" == "-1" ]]; then
    # Fetch latest start_date from ServiceNow
    NEW_START_DATE_UTC=$(echo "$POLL_RESPONSE" | grep -o '"start_date":"[^"]*' | sed 's/"start_date":"//' | cut -d'"' -f1)

    if [ -n "$NEW_START_DATE_UTC" ]; then
      SCHEDULED_EPOCH=$(date -d "$NEW_START_DATE_UTC UTC" +%s)
      NOW_EPOCH=$(date +%s)

      if [ $SCHEDULED_EPOCH -gt $NOW_EPOCH ]; then
        WAIT_DURATION=$(( SCHEDULED_EPOCH - NOW_EPOCH ))
        echo "🕓 Updated Scheduled Start (UTC): $NEW_START_DATE_UTC" | tee -a "$LOG_FILE"
        echo "⏳ Waiting $WAIT_DURATION seconds until scheduled time..." | tee -a "$LOG_FILE"
        sleep $WAIT_DURATION
      fi
    fi

    echo "🚀 Change Request is in 'Implement' state. Proceeding with deployment." | tee -a "$LOG_FILE"
    break
  fi

  COUNT=$((COUNT + 1))
  echo "⏳ Waiting... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

if [ $COUNT -ge $MAX_RETRIES ]; then
  echo "❌ Timeout while monitoring Change Request stages." | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request automation completed successfully." | tee -a "$LOG_FILE"
exit 0
