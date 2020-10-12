#!/bin/bash
NOW=$(date '+%Y%m%d%H%M%S')
LOGFILE="liveresults_sos.log"

while true
do
    ("./get_latest_results_sos_summary.sh") | tee -a $LOGFILE
    # ("./get_latest_results_sos_president_precinct.sh") | tee -a $LOGFILE  # Day after

    # ("./get_latest_results_sos_minneapolis.sh") | tee -a $LOGFILE
    sleep 20
done
