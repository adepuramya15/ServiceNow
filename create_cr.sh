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
    \"assignment_group\": \"$ASSIGNMENT_GROUP\",
    \"assigned_to\": \"$ASSIGNED_TO_SYS_ID\"
  }")

CHANGE_REQUEST_ID=$(echo "$CREATE_RESPONSE" | grep -o '"sys_id":"[^"]*' | sed 's/"sys_id":"//')
CHANGE_REQUEST_NUMBER=$(echo "$CREATE_RESPONSE" | grep -o '"number":"[^"]*' | sed 's/"number":"//')

if [ -z "$CHANGE_REQUEST_ID" ]; then
  echo "❌ Failed to extract Change Request ID" | tee -a "$LOG_FILE"
  echo "$CREATE_RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi

echo "✅ Change Request ID: $CHANGE_REQUEST_ID" | tee -a "$LOG_FILE"
echo "📌 Change Request Number: $CHANGE_REQUEST_NUMBER" | tee -a "$LOG_FILE"

# === STEP 3: Update Planning Fields ===
echo "🔄 Updating planning fields..." | tee -a "$LOG_FILE"
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
  }" > /dev/null

# === STEP 4: Monitor CR Progress ===
STAGES=("Assess" "Authorize" "Scheduled" "Implement")
MAX_RETRIES=60
SLEEP_INTERVAL=30
CURRENT_STAGE_INDEX=0

while [ $CURRENT_STAGE_INDEX -lt ${#STAGES[@]} ]; do
  CURRENT_STAGE="${STAGES[$CURRENT_STAGE_INDEX]}"
  echo "🔍 Waiting for stage: $CURRENT_STAGE..." | tee -a "$LOG_FILE"

  COUNT=0
  while [ $COUNT -lt $MAX_RETRIES ]; do
    RESPONSE=$(curl --silent --user "$SN_USER:$SN_PASS" \
      "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID")

    STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*' | sed 's/"state":"//')
    APPROVAL=$(echo "$RESPONSE" | grep -o '"approval":"[^"]*' | sed 's/"approval":"//')

    case "$CURRENT_STAGE" in
      "Assess" )    TARGET_STATE="-4" ;;
      "Authorize" ) TARGET_STATE="-3" ;;
      "Scheduled" ) TARGET_STATE="-2" ;;
      "Implement" ) TARGET_STATE="-1" ;;
    esac

    if [[ "$STATE" == "$TARGET_STATE" ]]; then
      echo "✅ Stage reached: $CURRENT_STAGE" | tee -a "$LOG_FILE"

      # === Scheduled stage logic with wait ===
      if [[ "$CURRENT_STAGE" == "Scheduled" ]]; then
        IST_NOW=$(TZ=Asia/Kolkata date +"%Y-%m-%d %H:%M:%S")
        START_UTC=$(TZ=Asia/Kolkata date -d "$IST_NOW" -u +"%Y-%m-%dT%H:%M:%SZ")
        END_UTC=$(TZ=Asia/Kolkata date -d "$IST_NOW +5 minutes" -u +"%Y-%m-%dT%H:%M:%SZ")

        echo "📅 Setting schedule window:" | tee -a "$LOG_FILE"
        echo "👉 UTC Start: $START_UTC" | tee -a "$LOG_FILE"
        echo "👉 UTC End  : $END_UTC" | tee -a "$LOG_FILE"

        curl --silent --request PATCH \
          "https://$SN_INSTANCE/api/now/table/change_request/$CHANGE_REQUEST_ID" \
          --user "$SN_USER:$SN_PASS" \
          --header "Content-Type: application/json" \
          --data "{ \"start_date\": \"$START_UTC\", \"end_date\": \"$END_UTC\" }" > /dev/null

        # Wait until the UTC time matches or exceeds scheduled start time
        echo "⏳ Waiting for UTC time to reach scheduled start time: $START_UTC" | tee -a "$LOG_FILE"
        while true; do
          CURRENT_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
          if [[ "$CURRENT_UTC" > "$START_UTC" || "$CURRENT_UTC" == "$START_UTC" ]]; then
            echo "✅ Scheduled time reached: $CURRENT_UTC" | tee -a "$LOG_FILE"
            break
          fi
          echo "⏱ Still waiting... Current UTC: $CURRENT_UTC" | tee -a "$LOG_FILE"
          sleep 10
        done
      fi

      # Proceed to next stage
      CURRENT_STAGE_INDEX=$((CURRENT_STAGE_INDEX + 1))
      break
    fi

    if [[ "$APPROVAL" == "rejected" ]]; then
      echo "❌ Change Request Rejected during $CURRENT_STAGE. Exiting." | tee -a "$LOG_FILE"
      exit 1
    fi

    echo "⏳ [$COUNT/$MAX_RETRIES] $CURRENT_STAGE not reached yet. Retrying in $SLEEP_INTERVAL sec..." | tee -a "$LOG_FILE"
    sleep $SLEEP_INTERVAL
    COUNT=$((COUNT + 1))
  done

  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Timeout waiting for stage: $CURRENT_STAGE. Exiting." | tee -a "$LOG_FILE"
    exit 1
  fi
done

echo "✅ All stages completed: Assess → Authorize → Scheduled → Implement" | tee -a "$LOG_FILE"
exit 0
