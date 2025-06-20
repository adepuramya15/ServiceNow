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

# === STEP 2: Create Change Request (Minimal initial payload to avoid timeout) ===
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

echo "📨 Response: $CREATE_RESPONSE" | tee -a "$LOG_FILE"

CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/\"sys_id\":\"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/\"number\":\"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 3: PATCH request to update planning fields and move to Assess ===
echo "🔄 Updating change request with planning fields..." | tee -a "$LOG_FILE"
UPDATE_RESPONSE=$(curl --silent --show-error --request PATCH \
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
  }")

echo "📨 Update Response: $UPDATE_RESPONSE" | tee -a "$LOG_FILE"

# === STEP 4: Monitor Stages ===
MAX_RETRIES=60
SLEEP_INTERVAL=30
COUNT=0
SCHEDULE_SET=false
DEPLOYED=false
SCHEDULE_WAIT_TS=0
LAST_STAGE=""
LAST_APPROVAL=""

while [ $COUNT -lt $MAX_RETRIES ]; do
  CURRENT_UTC=$(date -u +"%Y-%m-%d %H:%M:%S")
  RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
    "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

  RAW_STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/\"state\":\"//')
  STATE_NAME="${STATE_MAP[$RAW_STATE]:-$RAW_STATE}"
  APPROVAL=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/\"approval\":\"//')

  echo "🕒 [$CURRENT_UTC] Stage: $STATE_NAME | Approval: $APPROVAL" | tee -a "$LOG_FILE"

  if [[ "$APPROVAL" == "rejected" ]]; then
    echo "❌ Change Request was rejected in '$STATE_NAME' stage. Exiting." | tee -a "$LOG_FILE"
    exit 1
  fi

  if [[ "$STATE_NAME" != "$LAST_STAGE" || "$APPROVAL" != "$LAST_APPROVAL" ]]; then
    case "$STATE_NAME" in
      "Assess")
        if [[ "$APPROVAL" == "requested" ]]; then
          echo "📝 Step 1: Awaiting approval in Assess stage." | tee -a "$LOG_FILE"
        elif [[ "$APPROVAL" == "approved" ]]; then
          echo "✅ Step 2: Assess approved. Moving to Authorize..." | tee -a "$LOG_FILE"
        fi
        ;;
      "Authorize")
        if [[ "$APPROVAL" == "requested" ]]; then
          echo "🔐 Step 3: Awaiting CAB approval in Authorize stage..." | tee -a "$LOG_FILE"
        elif [[ "$APPROVAL" == "approved" ]]; then
          echo "✅ Step 4: CAB approved. Proceeding to Scheduled..." | tee -a "$LOG_FILE"
        fi
        ;;
      "Scheduled")
        echo "📆 Step 5: Change is Scheduled. Preparing deployment window..." | tee -a "$LOG_FILE"
        if [ "$SCHEDULE_SET" == false ]; then
          NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
          END=$(date -u -d "+10 minutes" +"%Y-%m-%dT%H:%M:%SZ")
          SCHEDULE_WAIT_TS=$(date -u -d "+1 seconds" +%s)

          curl --silent --request PATCH \
            "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID" \
            --user "$SN_USER:$SN_PASS" \
            --header "Content-Type: application/json" \
            --data "{ \"start_date\": \"$NOW\", \"end_date\": \"$END\" }" > /dev/null

          echo "🗓️ Schedule set: START=$NOW | END=$END | Deploying after TS=$SCHEDULE_WAIT_TS" | tee -a "$LOG_FILE"
          SCHEDULE_SET=true
        fi
        ;;
      "Implement")
        echo "🔧 Step 6: In Implement stage. Verifying deployment time..." | tee -a "$LOG_FILE"
        ;;
      "Closed"|"Cancelled")
        echo "❌ Change Request ended in '$STATE_NAME'. Exiting." | tee -a "$LOG_FILE"
        exit 1
        ;;
    esac
    LAST_STAGE="$STATE_NAME"
    LAST_APPROVAL="$APPROVAL"
  fi

  if [[ "$STATE_NAME" == "Implement" && "$DEPLOYED" == false ]]; then
    CURRENT_TS=$(date -u +%s)
    if [[ "$CURRENT_TS" -ge "$SCHEDULE_WAIT_TS" ]]; then
      echo "🚀 Step 7: Deployment starting..." | tee -a "$LOG_FILE"
      sleep 5  # Replace with your actual deployment logic
      echo "✅ Step 8: Deployment successful." | tee -a "$LOG_FILE"
      DEPLOYED=true
      exit 0
    else
      REMAINING=$((SCHEDULE_WAIT_TS - CURRENT_TS))
      echo "⏳ Waiting for deployment time... $REMAINING seconds remaining." | tee -a "$LOG_FILE"
    fi
  fi

  COUNT=$((COUNT + 1))
  echo "🔁 Retrying in $SLEEP_INTERVAL seconds... ($COUNT/$MAX_RETRIES)" | tee -a "$LOG_FILE"
  sleep $SLEEP_INTERVAL
done

echo "❌ Timeout reached. Implement stage not completed." | tee -a "$LOG_FILE"
exit 1
