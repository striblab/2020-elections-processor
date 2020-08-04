#!/bin/bash
set -o allexport; source .env; set +o allexport

LATEST_FILE=json/results-sos-statewide-latest.json

download_datetime=$(date '+%Y%m%d%H%M%S');
update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/results-sos-statewide-$download_datetime.json.XXXXXXX")

# Summary data
echo "Downloading U.S. House results, start summary file ..." &&
echo "state;county_id;precinct_id;office_id;office_name;district;\
cand_order;cand_name;suffix;incumbent;party;precincts_reporting;\
precincts_voting;votes;votes_pct;votes_office;officetype" | \
  cat - <(curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/ushouse.txt | sed -e 's/$/;U.S. House/') > sos/mn_2020_primary_aug_sos__statewide.csv

echo "Downloading U.S. Senate results, append to summary file ..." &&
curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/ussenate.txt | sed -e 's/$/;U.S. Senate/' >> sos/mn_2020_primary_aug_sos__statewide.csv

echo "Downloading MN Senate results, append to summary file ..." &&
curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/stsenate.txt | textutil -cat txt -stdin -stdout -encoding utf-8 | sed -e 's/DuprÈ/Dupré/' | sed -e 's/$/;MN State Senate/' >> sos/mn_2020_primary_aug_sos__statewide.csv

echo "Downloading MN House results, append to summary file ..." &&
curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/LegislativeByDistrict.txt | sed -e 's/$/;MN State House/' >> sos/mn_2020_primary_aug_sos__statewide.csv

echo "Downloading city results, append to summary file ..." &&
curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/local.txt | sed -e 's/$/;Local/' >> sos/mn_2020_primary_aug_sos__statewide.csv

echo "Replacing quotes temporarily..."
sed -i .bak 's/\"/@@/g' sos/mn_2020_primary_aug_sos__statewide.csv

echo "Converting summary file to JSON..." &&
csv2json -s ";" sos/mn_2020_primary_aug_sos__statewide.csv | \
  sed 's/@@/\\"/g' | \
  ndjson-cat | \
  ndjson-split > sos/mn_2020_primary_aug_sos__statewide.ndjson

cat sos/mn_2020_primary_aug_sos__statewide.ndjson | \
  ndjson-map "{'officename': d.officetype, 'statepostal': 'MN', 'full_name': d.cand_name, 'party': d.party, 'votecount': d.votes, 'votepct': d.votes_pct, 'winner': false, 'level': 'statewide', 'precinctsreporting': d.precincts_reporting, 'precinctstotal': d.precincts_voting, 'precinctsreportingpct': (d.precincts_reporting / d.precincts_voting).toFixed(2), 'seatname': d.office_name, 'fipscode': null, 'county_id_sos': d.county_id, 'lastupdated': '$update_datetime'}" | \
  ndjson-filter 'd.party == "DFL" || d.party == "R"' | \
  ndjson-reduce 'p.push(d), p' '[]' > $TMPFILE

printf "\n\n"

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

bool_update=false
# Test that this is a seemingly valid file
FIRST_LEVEL="$(cat $TMPFILE | jq '[.[]][0].level')"
if [ $FIRST_LEVEL == '"statewide"' ]; then
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
    gzip -vc $LATEST_FILE | aws s3 cp - "s3://$ELEX_S3_URL/json/results-sos-statewide-$download_datetime.json" \
    --profile $AWS_PROFILE_NAME \
    --acl public-read \
    --content-type=application/json \
    --content-encoding gzip

    # Make local timestamped file for new changed version
    cp $TMPFILE "json/results-sos-statewide-$download_datetime.json"


    # Check response headers
    RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE)
    if [ $RESPONSE_CODE == '200' ]; then
      echo "Successfully test-retrieved 'latest' file from S3."
    else
      echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
    fi

    # Get first entry of uploaded json
    FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]')
    if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"statewide"' ]; then
      echo "$FIRST_ENTRY"
    else
      echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable JSON in expected format. *****"
    fi
  fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
