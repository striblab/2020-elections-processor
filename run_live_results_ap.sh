#!/bin/bash
NOW=$(date '+%Y%m%d%H%M%S')
LOGFILE="liveresults_ap.log"

while true
do
    ("./get_latest_results_ap.sh") | tee -a $LOGFILE
    ("./get_latest_results_sos_minneapolis.sh") | tee -a $LOGFILE
    sleep 20
done
