#!/bin/bash
set -o allexport; source .env; set +o allexport

# Hey when this is really real be sure to turn off the --test flag

# For Minnesota March primary
ELECTION_DATE="03-03-2020"
STATE_NAME="Minnesota"
RACE_ID="25869"
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
echo $ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --results-level ru$TEST --raceids $RACE_ID -o json
$ELEX_INSTALLATION_PREFIX/elex results $ELECTION_DATE --results-level ru$TEST --raceids $RACE_ID -o json \
| jq -c "[
    .[]
    | select(.statename == \"$STATE_NAME\" )
    | select(.officename == \"President\")
    | select(.level == \"state\" or .level == \"county\")
    | {
      officename: .officename,
      statepostal: .statepostal,
      first: .first,
      last: .last,
      party: .party,
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
| [.[]]" > $TMPFILE

# Use these to undeclare an AP winner and/or declare a manual winner
# | [.[] | .winner = false]
# | . |= map(if .last == \"$MANUAL_WINNER\" then (.manual_winner=true) else . end)

# Use this to hardcode something else for testing
# [.[] | .lastupdated = \"1999-09-02 00:00:00\"] | [.[] | .votecount = 7] |

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
     gzip -vc $TMPFILE | aws s3 cp - "s3://$ELEX_S3_URL/json/results-$download_datetime.json" \
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
