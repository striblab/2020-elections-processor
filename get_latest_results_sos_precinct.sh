#!/bin/bash
set -o allexport; source .env; set +o allexport

LATEST_FILE=json/results-sos-precinct-latest.json

download_datetime=$(date '+%Y%m%d%H%M%S');
# update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/results-sos-precinct-$download_datetime.json.XXXXXXX")
# curl_easy_setopt(curl, CURLOPT_FILETIME, 1);

echo "Downloading precinct results ..." &&
echo "state;county_id;precinct_id;office_id;office_name;district;\
cand_order;cand_name;suffix;incumbent;party;precincts_reporting;\
precincts_voting;votes;votes_pct;votes_office" | \
  cat - <(curl -s --ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/allracesbyprecinct.txt | sed 's/\"/@@/g') > sos/mn_2020_primary_aug_sos__allracesbyprecinct.csv  # Replacing quotes with @@ temporarily, undone after json conversion completed in next step

# This doesn't currently seem to wkr -- it just gives the current server time. Might need to diff the actual file.
PRECINCTS_MODIFIED_TIME=$(curl -sI --ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/allracesbyprecinct.txt | grep -i Last-Modified | sed 's/Last-Modified: //g' | date | date '+%Y-%m-%dT%H:%M:%S')
echo $PRECINCTS_MODIFIED_TIME

csv2json -s ";" sos/mn_2020_primary_aug_sos__allracesbyprecinct.csv | \
  sed 's/@@/\\"/g' | \
  ndjson-cat | \
  ndjson-split > sos/mn_2020_primary_aug_sos__allracesbyprecinct.ndjson

cat sos/mn_2020_primary_aug_sos__allracesbyprecinct.ndjson | \
  ndjson-map "{'officename': d.office_name, 'statepostal': 'MN', 'full_name': d.cand_name, 'votecount': d.votes, 'votepct': d.votes_pct, 'winner': false, 'level': 'precinct', 'seatname': d.office_name, 'fipscode': null, 'county_id_sos': d.county_id, 'lastupdated': '$PRECINCTS_MODIFIED_TIME'}" | \
  ndjson-reduce 'p.push(d), p' '[]' > $TMPFILE

printf "\n\n"

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

# Test that this is a seemingly valid file
FIRST_LEVEL="$(cat $TMPFILE | jq '[.[]][0].level')"
if [ $FIRST_LEVEL == '"precinct"' ]; then
  echo "Seems to be JSON in expected AP-like format. Checking for changes from last version."

  if cmp --silent $TMPFILE $LATEST_FILE; then
     echo "File unchanged. No upload will be attempted."
  else
     echo "Changes found. Updating latest file..."
     cp $TMPFILE $LATEST_FILE

     # Push "latest" to s3
     gzip -vc $LATEST_FILE | aws s3 cp - s3://$ELEX_S3_URL/$LATEST_FILE \
     --profile $AWS_PROFILE_NAME \
     --acl public-read \
     --content-type=application/json \
     --content-encoding gzip

     # Push timestamped to s3
     gzip -vc $LATEST_FILE | aws s3 cp - "s3://$ELEX_S3_URL/json/results-sos-precinct-$download_datetime.json" \
     --profile $AWS_PROFILE_NAME \
     --acl public-read \
     --content-type=application/json \
     --content-encoding gzip

     # Make local timestamped file for new changed version
     cp $TMPFILE "json/results-sos-precinct-$download_datetime.json"
  fi

   # Check response headers
   RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE)
   if [ $RESPONSE_CODE == '200' ]; then
     echo "Successfully test-retrieved 'latest' file from S3."
   else
     echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
   fi

   # Get first entry of uploaded json
   FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]')
   if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"precinct"' ]; then
     echo "$FIRST_ENTRY"
   else
     echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable JSON in expected format. *****"
   fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
