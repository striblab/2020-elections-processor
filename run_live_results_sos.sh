#!/bin/bash
NOW=$(date '+%Y%m%d%H%M%S')
LOGFILE="liveresults_sos.log"

while true
do
    ("./get_latest_results_sos_summary.sh") | tee -a $LOGFILE
    sleep 20
done
