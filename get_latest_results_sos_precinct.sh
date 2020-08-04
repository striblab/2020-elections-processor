#!/bin/bash
set -o allexport; source .env; set +o allexport

LATEST_FILE=json/results-sos-precinct-latest.json

download_datetime=$(date '+%Y%m%d%H%M%S');
update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/results-sos-precinct-$download_datetime.json.XXXXXXX")

# Make json/csv directories if they don't exist
[ -d json ] || mkdir json
[ -d csv ] || mkdir csv

echo "Downloading precinct results ..." &&
echo "state;county_id;precinct_id;office_id;office_name;district;\
cand_order;cand_name;suffix;incumbent;party;precincts_reporting;\
precincts_voting;votes;votes_pct;votes_office" | \
  cat - <(curl -s --ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/allracesbyprecinct.txt | textutil -cat txt -stdin -stdout -encoding utf-8 | sed -e 's/DuprÈ/Dupré/' | sed 's/\"/@@/g') > sos/mn_2020_primary_aug_sos__allracesbyprecinct.csv  # Replacing quotes with @@ temporarily, undone after json conversion completed in next step

echo "Downloading city and school district races, append to precincts file ..." &&
curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/localPrct.txt | textutil -cat txt -stdin -stdout -encoding utf-8  | sed 's/\"/@@/g' >> sos/mn_2020_primary_aug_sos__allracesbyprecinct.csv

csv2json -s ";" sos/mn_2020_primary_aug_sos__allracesbyprecinct.csv | \
  sed 's/@@/\\"/g' | \
  ndjson-cat | \
  ndjson-split > sos/mn_2020_primary_aug_sos__allracesbyprecinct.ndjson

cat sos/mn_2020_primary_aug_sos__allracesbyprecinct.ndjson | \
  ndjson-map "{'officename': (d.office_name == 'U.S. Senator' ? 'U.S. Senate' : d.office_name.indexOf('U.S. Representative') != -1 ? 'U.S. House' : d.office_name.indexOf('State Representative') != -1 ? 'State House' : d.office_name.indexOf('State Senator') != -1 ? 'State Senate' : d.office_name.indexOf('QUESTION') != -1 ? 'Question' : 'Local'), 'seatname': d.office_name, 'full_name': d.cand_name, 'party': d.party, 'votecount': d.votes, 'votepct': d.votes_pct, 'winner': false, 'level': 'precinct', 'fipscode': null, 'county_id_sos': d.county_id, 'lastupdated': '$update_datetime'}" | \
  ndjson-filter 'd.party == "DFL" || d.party == "R"' | \
  ndjson-reduce 'p.push(d), p' '[]' > $TMPFILE

json2csv -i $TMPFILE > csv/results-sos-precinct-latest.csv

printf "\n\n"

bool_update=false
# Test that this is a seemingly valid file
FIRST_LEVEL="$(cat $TMPFILE | jq '[.[]][0].level')"
if [ $FIRST_LEVEL == '"precinct"' ]; then
  echo "Seems to be JSON in expected AP-like format. Checking for changes from last version."

  if test -f $LATEST_FILE; then
      echo "Checking for differences with last file..."
      new_comparison="$(cat $TMPFILE | ndjson-split | ndjson-map '{"vc": d.votecount, "pr": d.precinctsreporting}')"
      existing_comparison="$(cat $LATEST_FILE | ndjson-split | ndjson-map '{"vc": d.votecount, "pr": d.precinctsreporting}')"

      if  [[ "$new_comparison" == "$existing_comparison" ]]; then
         echo "File unchanged. No upload will be attempted."
      else
         echo "Changes found. Updating latest file..."
         cp $TMPFILE $LATEST_FILE
         bool_update=true
      fi
  else
      echo "No existing latest file, making one and uploading..."
      cp $TMPFILE $LATEST_FILE
      bool_update=true
  fi

  if $bool_update; then
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
  fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
