#!/bin/bash
NOW=$(date '+%Y%m%d%H%M%S')
LOGFILE="liveresults.log"

while true
do
    ("./get_latest_results.sh") | tee -a $LOGFILE
    sleep 28
done
