#!/bin/bash
 
# Hardcoded Splunk HEC values
SPLUNK_URL="https://prd-p-lpdzf.splunkcloud.com"
HEC_TOKEN="e20dfd26-400a-44ec-99d8-f0bab04ea955"
  
# Specify the log file and source ltype directly here
LOGFILE="logs/transaction.log"         # ✅ Change this to your desired log file
SOURCETYPE="Omsairam"               # ✅ Change this to your desired source type
INDEX="my_harness_index"     # ✅ Change this to your desired index
 
# Debug info
echo "Sending logs to: $SPLUNK_URL"
echo "Using sourcetype: $SOURCETYPE"
echo "Using index: $INDEX"
echo "Log file: $LOGFILE"
 
# Validate the log file exists
if [[ -f "$LOGFILE" ]]; then
  echo "📤 Sending $LOGFILE to Splunk..."
  while IFS= read -r line; do
    curl --silent --output /dev/null \
      -k "$SPLUNK_URL:8088/services/collector" \
      -H "Authorization: Splunk $HEC_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"event\": \"$line\", \"sourcetype\": \"$SOURCETYPE\", \"index\": \"$INDEX\"}" \
      --write-out '{"text":"Success","code":0}\n'
  done < "$LOGFILE"
else
  echo "❌ Log file not found: $LOGFILE"
  exit 1
fi
 
echo "✅ Deployment finished!"
