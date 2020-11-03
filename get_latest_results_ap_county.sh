#!/bin/bash
set -o allexport; source .env; set +o allexport

# Hey when this is really real be sure to turn off the --test flag

# For Minnesota Nov general
ELECTION_DATE="2020-11-03"
STATE_NAME="Minnesota"
# RACE_ID="25869"
RESULTS_LEVEL="ru"
# TEST=' --test'
TEST=''
MANUAL_WINNER=""  # Use this to override an AP race call (or lack thereof)

# For Minnesota August primary
# ELECTION_DATE="08-11-2020"
# STATE_NAME="Minnesota"
# # RACE_ID="25869"
# RESULTS_LEVEL="state"
# # TEST=' --test'
# TEST=''
# MANUAL_WINNER=""  # Use this to override an AP race call (or lack thereof)

download_datetime=$(date '+%Y%m%d%H%M%S');

LATEST_FILE=json/results-mn-county-latest.json

TMPFILE=$(mktemp "/tmp/results-mn-county-latest-$download_datetime.json.XXXXXXX")

printf "\n\n"

printf "Starting AP county update ...\n\n"

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

# Get latest results, send to date-stamped file
# echo $ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --results-level ru$TEST --raceids $RACE_ID -o json
# elex results 08-11-2020 --results-level state --test -o json
$ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --raceids 25151,0 --results-level $RESULTS_LEVEL$TEST -o json \
| jq -c "[
    .[]
    | select(
      (.statename == \"$STATE_NAME\")
      and (.level == \"state\" or .level == \"county\")
      and (.officename == \"U.S. Senate\" or .officename == \"President\")
      and (.officename | contains(\"Court\") | not )
    ) | {
      officename: .officename,
      statepostal: .statepostal,
      first: .first,
      last: .last,
      party: .party,
      uncontested: .uncontested,
      incumbent: .incumbent,
      votecount: .votecount,
      votepct: .votepct,
      winner: .winner,
      level: .level,
      precinctsreporting: .precinctsreporting,
      precinctstotal: .precinctstotal,
      precinctsreportingpct: .precinctsreportingpct,
      seatname: .seatname,
      fipscode: .fipscode,
      reportingunitid: .reportingunitid,
      reportingunitname: .reportingunitname,
      lastupdated: .lastupdated
    }
]
| [.[]]" > $TMPFILE

    # | select(.uncontested == false)

# Use these to undeclare an AP winner and/or declare a manual winner
# | [.[] | .winner = false]
# | . |= map(if .last == \"$MANUAL_WINNER\" then (.manual_winner=true) else . end)

# Use this to zero out before live results come in
#| [.[] | .lastupdated = \"2020-10-30 12:00:00\"] | [.[] | .votecount = 0] | [.[] | .votepct = 0] | [.[] | .winner = false] | [.[] | .precinctsreporting = 0 | .precinctsreportingpct = 0]

# Use this to hardcode something else for testing
# | [.[] | .lastupdated = \"1988-01-01 00:00:00\"] | [.[] | .votecount = 7500] | [.[] | .precinctsreporting = 66 | .precinctsreportingpct = 0.66]

# Test that this is a seemingly valid file
FIRST_LEVEL="$(cat $TMPFILE | jq '[.[]][0].level')"
if [ $FIRST_LEVEL == '"state"' ]; then
  echo "Seems to be JSON in expected elex format. Checking for changes from last version."

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
     gzip -vc $TMPFILE | aws s3 cp - "s3://$ELEX_S3_URL/json/versions/results-mn-county-latest-$download_datetime.json" \
     --profile $AWS_PROFILE_NAME \
     --acl public-read \
     --content-type=application/json \
     --content-encoding gzip

     # Make local timestamped file for new changed version
     cp $TMPFILE "json/results-$download_datetime.json"
  fi

   # Check response headers
   RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE)
   if [ $RESPONSE_CODE == '200' ]; then
     echo "Successfully test-retrieved 'latest' file from S3."
   else
     echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
   fi

   # curl -I $ELEX_S3_URL/$LATEST_FILE

   # Get first entry of uploaded json
   # FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]')
   # Override: Get an interesting race
   FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[] | select(.last == "Trump")][0]')
   if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"state"' ]; then
     echo "$FIRST_ENTRY"
   else
     echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable JSON in expected format. *****"
   fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
