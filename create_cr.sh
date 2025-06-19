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

# === Planning Fields ===
JUSTIFICATION="Integrating Splunk logging into Harness CI/CD pipeline for enhanced monitoring and automated event visibility."
IMPLEMENTATION_PLAN="1. Configure Splunk HEC endpoint\n2. Push logs from Harness CI pipeline\n3. Validate log ingestion\n4. Monitor dashboards and alerts"
RISK_AND_IMPACT_ANALYSIS="Risk is minimal. If Splunk fails to receive logs, fallback logging remains active on Jenkins and Harness. No disruption expected."
BACKOUT_PLAN="Revert to default Jenkins logging by disabling Splunk steps in the pipeline."
TEST_PLAN="Trigger CI/CD job, verify that logs are received in Splunk index, and validate using search query."

# === Scheduling Fields (initial dummy values) ===
PLANNED_START_DATE="2025-06-19 12:18:00"
PLANNED_END_DATE="2025-06-19 13:48:00"
CAB_DATE="2025-06-19 13:18:00"
ACTUAL_START_DATE=""
ACTUAL_END_DATE=""
CAB_REQUIRED="true"
CAB_DELEGATE="Change Advisory Board"
CAB_RECOMMENDATION="Approved - Proceed with minimal risk"

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
        \"business_service\": \"$BUSINESS_SERVICE\",
        \"service_offering\": \"$SERVICE_OFFERING\",
        \"justification\": \"$JUSTIFICATION\",
        \"implementation_plan\": \"$IMPLEMENTATION_PLAN\",
        \"risk_and_impact_analysis\": \"$RISK_AND_IMPACT_ANALYSIS\",
        \"backout_plan\": \"$BACKOUT_PLAN\",
        \"test_plan\": \"$TEST_PLAN\",
        \"start_date\": \"$PLANNED_START_DATE\",
        \"end_date\": \"$PLANNED_END_DATE\",
        \"cab_required\": \"$CAB_REQUIRED\",
        \"cab_date\": \"$CAB_DATE\",
        \"work_start\": \"$ACTUAL_START_DATE\",
        \"work_end\": \"$ACTUAL_END_DATE\",
        \"cab_delegate\": \"$CAB_DELEGATE\",
        \"cab_recommendation\": \"$CAB_RECOMMENDATION\",
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

# === STEP 4: Monitor Each Stage ===
echo "⏳ Waiting for stage transitions: Assess → Authorize → Scheduled → Implement" | tee -a "$LOG_FILE"

MAX_RETRIES=120
SLEEP_INTERVAL=30
COUNT=0
STAGE_PASSED=""

while [ $COUNT -lt $MAX_RETRIES ]; do
  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/"state":"//')
  APPROVAL=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/"approval":"//')
  START_DATE=$(echo "$RESPONSE" | grep -o '"start_date":"[^"]*' | sed 's/"start_date":"//' | cut -d'"' -f1)

  case "$STATE" in
    "Assess")
      echo "📝 Current Stage: Assess | Approval: $APPROVAL" | tee -a "$LOG_FILE"
      ;;
    "Authorize")
      if [[ "$STAGE_PASSED" != *"Authorize"* ]]; then
        echo "🔐 Moved to Authorize | Approval: $APPROVAL" | tee -a "$LOG_FILE"
        UTC_NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
        echo "🌐 Current UTC Time: $UTC_NOW" | tee -a "$LOG_FILE"
        echo "👉 Use this UTC time as the Scheduled Start Date in ServiceNow to proceed immediately." | tee -a "$LOG_FILE"
        STAGE_PASSED+="Authorize "
      fi
      ;;
    "Scheduled")
      if [[ "$STAGE_PASSED" != *"Scheduled"* ]]; then
        echo "📅 Moved to Scheduled | Waiting for: $START_DATE" | tee -a "$LOG_FILE"

        CURRENT_EPOCH=$(date +%s)
        START_EPOCH=$(date -d "$START_DATE" +%s)
        WAIT_TIME=$((START_EPOCH - CURRENT_EPOCH))
        if (( WAIT_TIME > 0 )); then
          echo "⏳ Sleeping $WAIT_TIME seconds until scheduled start time..." | tee -a "$LOG_FILE"
          sleep $WAIT_TIME
        else
          echo "⏩ Scheduled time already passed. Moving forward..." | tee -a "$LOG_FILE"
        fi

        STAGE_PASSED+="Scheduled "
      fi
      ;;
    "Implement")
      echo "🚀 Reached Implement Stage | Ready to Execute!" | tee -a "$LOG_FILE"
      echo "✅ Final stage reached. Exiting successfully." | tee -a "$LOG_FILE"
      exit 0
      ;;
    "Closed" | "Cancelled")
      echo "❌ Request ended in '$STATE' state. Aborting." | tee -a "$LOG_FILE"
      exit 1
      ;;
    *)
      echo "🔄 Current Stage: $STATE | Approval: $APPROVAL | Waiting..." | tee -a "$LOG_FILE"
      ;;
  esac

  COUNT=$((COUNT + 1))
  echo "Retrying in $SLEEP_INTERVAL seconds... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout: Implement stage was not reached in time." | tee -a "$LOG_FILE"
exit 1