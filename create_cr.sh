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

echo "📦 Creating change request..." | tee "$LOG_FILE"

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
        \"cab_required\": \"$CAB_REQUIRED\",
        \"cab_delegate\": \"$CAB_DELEGATE\",
        \"cab_recommendation\": \"$CAB_RECOMMENDATION\",
        \"state\": \"Assess\"
      }")

echo "📨 Response: $CREATE_RESPONSE" | tee -a "$LOG_FILE"

# === STEP 3: Extract sys_id and number ===
CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/"sys_id":"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/"number":"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 4: Monitor Change ===
MAX_RETRIES=120
SLEEP_INTERVAL=30
COUNT=0
SCHEDULED_TIME_WAITED=false
DEPLOYED=false

while [ $COUNT -lt $MAX_RETRIES ]; do
  CURRENT_UTC=$(date -u +"%Y-%m-%d %H:%M:%S")
  echo "🕒 Current UTC Time: $CURRENT_UTC" | tee -a "$LOG_FILE"

  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  RAW_STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/"state":"//')
  STATE_NAME="${STATE_MAP[$RAW_STATE]:-$RAW_STATE}"
  APPROVAL=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/"approval":"//')

  echo "🔄 Stage: $STATE_NAME | Approval: $APPROVAL" | tee -a "$LOG_FILE"

  # === Set start_date = now when in Scheduled state
  if [[ "$STATE_NAME" == "Scheduled" && "$SCHEDULED_TIME_WAITED" == false ]]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    END=$(date -u -d "+10 minutes" +"%Y-%m-%dT%H:%M:%SZ")

    echo "🗓️ Setting schedule to START: $NOW and END: $END" | tee -a "$LOG_FILE"

    curl --silent --request PATCH \
      "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID" \
      --user "$SN_USER:$SN_PASS" \
      --header "Content-Type: application/json" \
      --data "{
        \"start_date\": \"$NOW\",
        \"end_date\": \"$END\"
      }" > /dev/null

    echo "⏳ Waiting 5 minutes after scheduling before allowing implement..." | tee -a "$LOG_FILE"
    sleep 300  # Wait 5 minutes
    SCHEDULED_TIME_WAITED=true
  fi

  # === Allow deploy only after 5 min wait and Implement stage
  if [[ "$STATE_NAME" == "Implement" && "$SCHEDULED_TIME_WAITED" == true && "$DEPLOYED" == false ]]; then
    echo "🚀 Implement stage reached after schedule wait — starting deployment..." | tee -a "$LOG_FILE"
    # === Your deployment trigger command goes here ===
    sleep 5
    echo "✅ Implemented Done. Deployment completed successfully." | tee -a "$LOG_FILE"
    DEPLOYED=true
    exit 0
  fi

  if [[ "$STATE_NAME" == "Closed" || "$STATE_NAME" == "Cancelled" ]]; then
    echo "❌ Change Request ended in '$STATE_NAME' state. Exiting." | tee -a "$LOG_FILE"
    exit 1
  fi

  COUNT=$((COUNT + 1))
  echo "⏳ Waiting $SLEEP_INTERVAL seconds before next check... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout: Change request did not reach Implement stage in expected time." | tee -a "$LOG_FILE"
exit 1
