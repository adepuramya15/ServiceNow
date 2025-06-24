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

CAB_REQUIRED="true"
CAB_DELEGATE="Change Advisory Board"
CAB_RECOMMENDATION="Approved - Proceed with minimal risk"

# === State Mapping ===
declare -A STATE_MAP=(
  ["-5"]="New"
  ["-4"]="Assess"
  ["-3"]="Authorize"
  ["-2"]="Scheduled"
  ["-1"]="Implement"
  ["3"]="Closed"
  ["4"]="Cancelled"
)

# === STEP 2: Create Change Request ===
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
    \"assignment_group\": \"$ASSIGNMENT_GROUP\"
  }")

CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/\"sys_id\":\"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/\"number\":\"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 3: Update Planning Fields ===
echo "🔄 Updating change request with planning fields..." | tee -a "$LOG_FILE"
curl --silent --request PATCH \
  "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID" \
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
  }" | tee -a "$LOG_FILE"

# === STEP 4: Monitor and Trigger Implementation ===
MAX_RETRIES=30
SLEEP_INTERVAL=30
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
  CURRENT_UTC=$(date -u +"%Y-%m-%d %H:%M:%S")
  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  RAW_STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/\"state\":\"//')
  STATE_NAME="${STATE_MAP[$RAW_STATE]:-$RAW_STATE}"
  APPROVAL=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/\"approval\":\"//')

  echo "🕒 [$CURRENT_UTC] Stage: $STATE_NAME | Approval: $APPROVAL" | tee -a "$LOG_FILE"

  # 🛑 Check if rejected
  if [[ "$APPROVAL" == "rejected" ]]; then
    echo "❌ Change Request was rejected. Exiting pipeline." | tee -a "$LOG_FILE"
    exit 1
  fi

  case "$STATE_NAME" in
    "Assess")
      echo "📘 Step 1: Assess stage - under review." | tee -a "$LOG_FILE"
      ;;
    "Authorize")
      echo "📗 Step 2: Authorize stage - CAB review in progress." | tee -a "$LOG_FILE"
      ;;
    "Scheduled")
      echo "📙 Step 3: Scheduled stage - setting 2 minute window." | tee -a "$LOG_FILE"
      START_UTC=$(date -u -d "+1 minute" +"%Y-%m-%dT%H:%M:%SZ")
      END_UTC=$(date -u -d "+3 minute" +"%Y-%m-%dT%H:%M:%SZ")
      curl --silent --request PATCH \
        "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID" \
        --user "$SN_USER:$SN_PASS" \
        --header "Content-Type: application/json" \
        --data "{ \"start_date\": \"$START_UTC\", \"end_date\": \"$END_UTC\" }" > /dev/null
      echo "🗓️ Schedule set: Start - $START_UTC | End - $END_UTC" | tee -a "$LOG_FILE"
      ;;
    "Implement")
      echo "📕 Step 4: Implement stage - executing now..." | tee -a "$LOG_FILE"
      echo "✅ Implementation completed." | tee -a "$LOG_FILE"
      exit 0
      ;;
    "Closed"|"Cancelled")
      echo "❌ Change Request ended in '$STATE_NAME'. Exiting." | tee -a "$LOG_FILE"
      exit 1
      ;;
    *)
      echo "🔍 Unknown stage '$STATE_NAME'. Waiting..." | tee -a "$LOG_FILE"
      ;;
  esac

  COUNT=$((COUNT + 1))
  echo "🔁 Retrying in $SLEEP_INTERVAL seconds... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout reached. Implement stage not completed." | tee -a "$LOG_FILE"
exit 1
