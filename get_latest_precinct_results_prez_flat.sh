#!/bin/bash
set -o allexport; source .env; set +o allexport

# Once we don't need the scraper anymore, this script translates the raw SOS text files into the same format for the front-end map

LATEST_FILE=csv/mn_2020_nov_sos__flat__president__precinct.csv

download_datetime=$(date '+%Y%m%d%H%M%S');
update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/mn_2020_nov_sos__flat__president__precinct-$download_datetime.csv.XXXXXXX")
# TMPFILE_FILTERED=$(mktemp "/tmp/mn_2020_nov_sos__scrape__filtered__president__precinct-$download_datetime.csv.XXXXXXX")


# Make csv directory if it doesn't exist
[ -d csv ] || mkdir csv

CSV_HEADER_ROW="state;county_id_sos;precinct_id;office_id;seatname;district;\
cand_order;full_name;suffix;incumbent;party;precinctsreporting;\
precinctstotal;votecount;votepct;votes_office"

echo "Loading latest SOS precinct file ..." &&
CURL_RESPONSE=$(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/USPresPct.txt)

if [ "${#CURL_RESPONSE}" -gt "100" ]; then
  echo "Got long response, proceeding..."
  echo -e "$CSV_HEADER_ROW\n$CURL_RESPONSE" | \
  iconv -f iso8859-1 -t utf-8 | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
    ndjson-map 'd.lookup = (d.county_id_sos + d.precinct_id), d' | \
    ndjson-join --left 'd.lookup' 'd.lookup' - <(cat supporting_tables/sos_precincts_lookup.ndjson) | \
    ndjson-map 'Object.assign(d[0], d[1])' | \
    ndjson-join --left 'd.county_id_sos' 'd.county_id_sos' - <(cat supporting_tables/sos_county_id_fips_lookup.ndjson) | \
    ndjson-map 'Object.assign(d[0], d[1])' | \
    ndjson-map "{'officename': 'pres', 'precinct_id': d.precinct_id, 'full_name': d.full_name, 'party': d.party, 'votecount': d.votecount, 'votepct': d.votepct, 'level': 'p', 'county_fips': d.fips, 'lastupdated': '$update_datetime'}" | \
    json2csv > $TMPFILE

    # Test that this is a seemingly valid file
    bool_update=false
    FIRST_LEVEL="$(head $TMPFILE | csv2json | jq '[.[]][0].level')"
    echo $FIRST_LEVEL
    if [ $FIRST_LEVEL == '"p"' ]; then
      echo "Seems to be CSV in expected AP-like format."

      if test -f $LATEST_FILE; then
          echo "Checking for differences with last file..."
          new_comparison="$(csv2json $TMPFILE | jq -c ".[]" | ndjson-map '{"vc": d.votecount}')"
          existing_comparison="$(csv2json $LATEST_FILE | jq -c ".[]" | ndjson-map '{"vc": d.votecount}')"

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
        gzip -vc $LATEST_FILE | $PYTHON_LOCATION/aws s3 cp - s3://$ELEX_S3_URL/$LATEST_FILE.gz \
        --profile $AWS_PROFILE_NAME \
        --acl public-read \
        --content-type=text/csv \
        --content-encoding gzip

        # Push timestamped to s3
        gzip -vc $LATEST_FILE | $PYTHON_LOCATION/aws s3 cp - "s3://$ELEX_S3_URL/csv/versions/mn_2020_nov_sos__flat__president__precinct-$download_datetime.csv.gz" \
        --profile $AWS_PROFILE_NAME \
        --acl public-read \
        --content-type=text/csv \
        --content-encoding gzip

        # Make local timestamped file for new changed version
        # cp $TMPFILE "csv/results-sos-statewide-$download_datetime.csv"

        # Check response headers
        RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE.gz)
        if [ $RESPONSE_CODE == '200' ]; then
          echo "Successfully test-retrieved 'latest' file from S3."
        else
          echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
        fi

        # Get first entry of uploaded CSV
        FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE.gz | head | csv2json | jq '[.[]][0]')
        if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"p"' ]; then
          echo "$FIRST_ENTRY"
        else
          echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable CSV in expected format. *****"
        fi
      fi
    else
      echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from this CSV. Taking no further action. *****"
    fi
else
  echo "WARNING: very short file..."
fi



#
#   # Test that this is a seemingly valid file
#   FIRST_LEVEL="$(head $TMPFILE_FILTERED | csv2json | jq '[.[]][0].level')"
#   echo $FIRST_LEVEL
#   if [ $FIRST_LEVEL == '"p"' ]; then
#     echo "Seems to be CSV in expected AP-like format."
#     cp $TMPFILE_FILTERED $LATEST_FILE
#
#     # Push "latest" to s3
#     gzip -vc $LATEST_FILE | $PYTHON_LOCATION/aws s3 cp - s3://$S3_URL/$LATEST_FILE.gz \
#     --profile $AWS_PROFILE_NAME \
#     --acl public-read \
#     --content-type=text/csv \
#     --content-encoding gzip
#
#     # Push timestamped to s3
#     gzip -vc $LATEST_FILE | $PYTHON_LOCATION/aws s3 cp - "s3://$S3_URL/csv/versions/mn_2020_nov_sos__scrape__filtered__president__precinct-$download_datetime.csv.gz" \
#     --profile $AWS_PROFILE_NAME \
#     --acl public-read \
#     --content-type=text/csv \
#     --content-encoding gzip
#
#     # Make local timestamped file for new changed version
#     # cp $TMPFILE "csv/results-sos-statewide-$download_datetime.csv"
#
#     # Check response headers
#     RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $S3_URL/$LATEST_FILE.gz)
#     if [ $RESPONSE_CODE == '200' ]; then
#       echo "Successfully test-retrieved 'latest' file from S3."
#     else
#       echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
#     fi
#
#     # Get first entry of uploaded CSV
#     FIRST_ENTRY=$(curl -s --compressed $S3_URL/$LATEST_FILE.gz | head | csv2json | jq '[.[]][0]')
#     if [ "$(echo $FIRST_ENTRY | jq '.level')" == '"p"' ]; then
#       echo "$FIRST_ENTRY"
#     else
#       echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable CSV in expected format. *****"
#     fi
#   else
#     echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from scrape CSV. Taking no further action. *****"
#   fi
#   printf "\n\n"
