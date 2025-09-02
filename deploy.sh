#!/bin/bash
 
# Hardcoded Splunk HEC values
SPLUNK_URL="https://prd-p-idagf.splunkcloud.com:8088"
HEC_TOKEN="a593068d-c9ac-4608-b36c-13708c8d40b2"
  
# Specify the log file and source ltype directly here
LOGFILE="logs/application.log"         # ✅ Change this to your desired log filess
SOURCETYPE="application_logs"               # ✅ Change this to your desired source type
INDEX="ramya-index"     # ✅ Change this to your desired index
 
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
      -k "$SPLUNK_URL/services/collector" \
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

#hii