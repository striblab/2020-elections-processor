#!/bin/bash
NOW=$(date '+%Y%m%d%H%M%S')
LOGFILE="liveresults_ap.log"

DO_SOS_SWITCH=true
LOOP_COUNT=5

while true
do
    ("./get_latest_results_ap_national.sh") | tee -a $LOGFILE

    sleep 7

    ("./get_latest_results_ap_statewide.sh") | tee -a $LOGFILE

    sleep 7

    ("./get_latest_results_ap_county.sh") | tee -a $LOGFILE

    sleep 7

    # Update local results every 5 loops
    echo SOS loop count: $LOOP_COUNT
    if [[ "$LOOP_COUNT" -gt 4 ]]; then
      ("./get_latest_results_sos_summary_with_joins.sh") | tee -a $LOGFILE
      ((LOOP_COUNT=1))
    else
      echo Skipping update
      ((LOOP_COUNT++))
    fi

done
