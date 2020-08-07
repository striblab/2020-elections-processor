#!/bin/bash
set -o allexport; source .env; set +o allexport

LATEST_FILE=json/results-sos-minneapolis-latest.json

download_datetime=$(date '+%Y%m%d%H%M%S');
update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/results-sos-minneapolis-$download_datetime.json.XXXXXXX")

# Summary data
echo "Downloading city results to summary file ..." &&
echo "state;county_id;precinct_id;office_id;office_name;district;\
cand_order;cand_name;suffix;incumbent;party;precincts_reporting;\
precincts_voting;votes;votes_pct;votes_office;officetype" | \
  cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20200811/local.txt | sed -e 's/$/;Local/') > sos/mn_2020_primary_aug_sos__minneapolis.csv

echo "Replacing quotes temporarily..."
# sed -i .bak 's/\"/@@/g' sos/mn_2020_primary_aug_sos__minneapolis.csv

echo "Converting summary file to JSON..." &&
csv2json -s ";" sos/mn_2020_primary_aug_sos__minneapolis.csv | \
  sed 's/@@/\\"/g' | \
  ndjson-cat | \
  ndjson-split > sos/mn_2020_primary_aug_sos__minneapolis.ndjson

cat sos/mn_2020_primary_aug_sos__minneapolis.ndjson | \
  ndjson-filter 'd.office_name.indexOf("(Minneapolis)") != -1' | \
  ndjson-map "{'officename': d.officetype, 'statepostal': 'MN', 'full_name': d.cand_name, 'party_orig': d.party, 'votecount': d.votes, 'votepct': d.votes_pct, 'winner': false, 'level': 'local', 'precinctsreporting': d.precincts_reporting, 'precinctstotal': d.precincts_voting, 'precinctsreportingpct': (d.precincts_reporting / d.precincts_voting).toFixed(2), 'seatname': d.office_name, 'fipscode': null, 'county_id_sos': d.county_id, 'party': (d.cand_name == 'AK Hassan' || d.cand_name == 'Michael P. Dougherty' || d.cand_name == 'Mohamoud Hassan' || d.cand_name == 'Nebiha Mohammed' || d.cand_name == 'Suud Olat' || d.cand_name == 'Jamal Osman' || d.cand_name == 'Alex Palacios' || d.cand_name == 'Saciido Shaie' || d.cand_name == 'Abdirizak Bihi' ? 'DFL' : d.cand_name == 'AJ Awed' ? 'Independent' : d.cand_name == 'Sara Mae Engberg' ? 'Humanity Forward' : d.cand_name == 'Joshua Scheunemann' ? 'Green Party' : ''), 'lastupdated': '$update_datetime'}" | \
  # Temp: zeros
  # ndjson-map 'd.votecount = 0, d' | \
  # ndjson-map 'd.votepct = 0, d' | \
  # ndjson-map 'd.precinctsreporting = 0, d' | \
  # ndjson-map 'd.precinctsreportingpct = 0, d' | \
  # End zeros
  ndjson-reduce 'p.push(d), p' '[]' > $TMPFILE

printf "\n\n"

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

bool_update=false
# Test that this is a seemingly valid file
FIRST_LEVEL="$(cat $TMPFILE | jq '[.[]][0].level')"
if [ $FIRST_LEVEL == '"local"' ]; then
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
    gzip -vc $LATEST_FILE | aws s3 cp - "s3://$ELEX_S3_URL/json/versions/results-sos-minneapolis-$download_datetime.json" \
    --profile $AWS_PROFILE_NAME \
    --acl public-read \
    --content-type=application/json \
    --content-encoding gzip

    # Make local timestamped file for new changed version
    cp $TMPFILE "json/results-sos-minneapolis-$download_datetime.json"


    # Check response headers
    RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE)
    if [ $RESPONSE_CODE == '200' ]; then
      echo "Successfully test-retrieved 'latest' file from S3."
    else
      echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
    fi

    # Get first entry of uploaded json
    FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]')
    if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"local"' ]; then
      echo "$FIRST_ENTRY"
    else
      echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable JSON in expected format. *****"
    fi
  fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
