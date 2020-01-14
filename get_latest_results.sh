#!/bin/bash

download_datetime=$(date '+%Y%m%d%H%M%S');

LATEST_FILE=json/results-test-latest.json

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

# Get latest results, send to date-stamped file
elex results 03-03-2020 --results-level ru --raceids 25869 --test -o json \
| jq -c '[
    .[] |
    select(.statename == "Minnesota" ) |
    select(.officename == "President") |
    {
      officename: .officename,
      statepostal: .statepostal,
      first: .first,
      last: .last,
      party: .party,
      votecount: .votecount,
      votepct: .votepct,
      winner: .winner,
      level: .level,
      fipscode: .fipscode,
      reportingunitname: .reportingunitname,
      lastupdated: .lastupdated
    }
 ]' > "json/results-test-$download_datetime.json"

# Test that this is a seemingly valid file
FIRST_OFFICENAME="$(cat "json/results-test-$download_datetime.json" | jq '[.[]][0].officename')"
if [ $FIRST_OFFICENAME == '"President"' ]; then
  echo "Seems to be JSON in expected elex format. Checking for changes from last version."

  if cmp --silent "json/results-test-$download_datetime.json" $LATEST_FILE; then
     echo "File unchanged. No upload will be attempted."
  else
     echo "Changes found. Updating latest file..."
     cp "json/results-test-$download_datetime.json" $LATEST_FILE

     gzip -vc $LATEST_FILE | aws s3 cp - s3://$ELEX_S3_URL/$LATEST_FILE \
     --acl public-read \
     --content-type=application/json \
     --content-encoding gzip
  fi

   # Check response headers
   curl -I $ELEX_S3_URL/$LATEST_FILE

   # Get first entry of uploaded json
   curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]'
else
  echo "The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action."
fi
