#!/bin/bash
set -o allexport; source .env; set +o allexport

# Hey when this is really real be sure to turn off the --test flag

# For Minnesota March primary
ELECTION_DATE="08-11-2020"
STATE_NAME="Minnesota"
# RACE_ID="25869"
RESULTS_LEVEL="state"
TEST=' --test'
# TEST=''
MANUAL_WINNER=""  # Use this to override an AP race call (or lack thereof)

# For New Hampshire primary
# ELECTION_DATE="02-11-2020"
# STATE_NAME="New Hampshire"
# RACE_ID="32115"
# # TEST=' --test'
# TEST=''
# # MANUAL_WINNER="Yang"  # Use this to override an AP race call (or lack thereof)


# For Iowa Caucuses
# ELECTION_DATE="02-03-2020"
# STATE_NAME="Iowa"
# RACE_ID="17278"
# # TEST=' --test'
# TEST=''
# MANUAL_WINNER=""  # Use this to override an AP race call (or lack thereof)

download_datetime=$(date '+%Y%m%d%H%M%S');

LATEST_FILE=json/results-latest.json

TMPFILE=$(mktemp "/tmp/results-$download_datetime.json.XXXXXXX")

printf "\n\n"

# Make json directory if it doesn't exist
[ -d json ] || mkdir json

# Get latest results, send to date-stamped file
# echo $ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --results-level ru$TEST --raceids $RACE_ID -o json
# elex results 08-11-2020 --results-level state --test -o json
$ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --results-level $RESULTS_LEVEL$TEST -o json \
| jq -c "[
    .[]
    | select(
      (.statename == \"$STATE_NAME\")
      and (.level == \"state\" or .level == \"county\")
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
| [.[] | .manual_winner = false]
# Use this to zero out before live results come in
| [.[] | .winner = false]  # Override AP winner calls for now
| [.[] | .lastupdated = \"2020-08-07 12:00:00\"] | [.[] | .votecount = 0] | [.[] | .votepct = 0] | [.[] | .winner = false] | [.[] | .precinctsreporting = 0 | .precinctsreportingpct = 0]
| [.[]]" > $TMPFILE

    # | select(.uncontested == false)

# Use these to undeclare an AP winner and/or declare a manual winner
# | [.[] | .winner = false]
# | . |= map(if .last == \"$MANUAL_WINNER\" then (.manual_winner=true) else . end)

# Use this to zero out before live results come in
#| [.[] | .lastupdated = \"2020-02-27 12:00:00\"] | [.[] | .votecount = 0] | [.[] | .votepct = 0] | [.[] | .winner = false] | [.[] | .precinctsreporting = 0 | .precinctsreportingpct = 0]

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
     gzip -vc $TMPFILE | aws s3 cp - "s3://$ELEX_S3_URL/json/versions/results-$download_datetime.json" \
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
   FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE | jq '[.[]][0]')
   if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"state"' ]; then
     echo "$FIRST_ENTRY"
   else
     echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable JSON in expected format. *****"
   fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex JSON. Taking no further action. *****"
fi
printf "\n\n"
