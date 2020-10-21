#!/bin/bash
set -o allexport; source .env; set +o allexport

download_datetime=$(date '+%Y%m%d%H%M%S');
update_datetime=$(date '+%Y-%m-%dT%H:%M:%S');  # For use in JSON

TMPFILE=$(mktemp "/tmp/results-sos-statewide-latest-$download_datetime.json.XXXXXXX")
LATEST_FILE=sos/results-sos-statewide-latest.csv

CSV_HEADER_ROW="state;county_id_sos;precinct_id;office_id;seatname;district;\
cand_order;full_name;suffix;incumbent;party;precinctsreporting;\
precinctstotal;votecount;votepct;votes_office"


echo "Downloading supreme/appeals court results, append to summary file ..." &&
echo $CSV_HEADER_ROW | \
cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/judicial.txt | iconv -f iso8859-1 -t utf-8) | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
  ndjson-map 'd.location_name = "", d' | \
  ndjson-map 'd.officename = "Supreme and Appeals Court", d' > sos/mn_2020_nov_sos__statewide.ndjson


echo "Downloading district court results, append to summary file ..." &&
echo $CSV_HEADER_ROW | \
cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/judicialdst.txt | iconv -f iso8859-1 -t utf-8) | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
  ndjson-map 'd.location_name = "", d' | \
  ndjson-map 'd.officename = "District Court", d' >> sos/mn_2020_nov_sos__statewide.ndjson


echo "Downloading county results, append to summary file ..." &&
echo $CSV_HEADER_ROW | \
cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/cntyRaceQuestions.txt | iconv -f iso8859-1 -t utf-8) | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
  ndjson-map 'd.location_name = "", d' | \
  ndjson-map 'd.officename = "County", d' >> sos/mn_2020_nov_sos__statewide.ndjson


echo "Downloading municipal results, merging with city lookup file, append to summary file ..."
echo $CSV_HEADER_ROW | \
cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/local.txt | iconv -f iso8859-1 -t utf-8) | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
  ndjson-join --left 'd.district' 'd.fips_code' - <(cat supporting_tables/sos_city_lookup.ndjson) | \
  ndjson-map 'Object.assign(d[0], d[1])' | \
  ndjson-map 'd.officename = "Local", d' | \
  ndjson-filter 'delete d.county_name, true' | ndjson-filter 'delete d.fips_code, true' >> sos/mn_2020_nov_sos__statewide.ndjson


echo "Downloading school board results, merging with school district lookup, append to summary file ..." &&
echo $CSV_HEADER_ROW | \
cat - <(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/SDRaceQuestions.txt | iconv -f iso8859-1 -t utf-8) | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
  ndjson-join --left 'd.district' 'd.school_dist_num' - <(cat supporting_tables/sos_school_lookup.ndjson) | \
  ndjson-map 'Object.assign(d[0], d[1])' | \
  ndjson-map 'd.officename = "School", d' | \
  ndjson-filter 'delete d.county_name, true' | ndjson-filter 'delete d.school_dist_num, true' >> sos/mn_2020_nov_sos__statewide.ndjson


echo "Filtering and adding Strib fields..."
cat sos/mn_2020_nov_sos__statewide.ndjson | \
  ndjson-filter 'd.full_name != "WRITE-IN"' | \
  ndjson-map 'd.precinctsreportingpct = (d.precinctsreporting / d.precinctstotal).toFixed(2), d' | \
  ndjson-map "d.lastupdated = '$update_datetime', d" | \
  ndjson-filter 'delete d.state, true' | ndjson-filter 'delete d.precinct_id, true' | ndjson-filter 'delete d.cand_order, true' | \
  json2csv -d ";" > $TMPFILE

# Make sos directory if it doesn't exist
[ -d sos ] || mkdir sos

bool_update=false
# Test that this is a seemingly valid file
FIRST_OFFICE="$(head -n 2 $TMPFILE | csv2json -s ";" | jq '.[0].officename')"
if [ "$FIRST_OFFICE" == '"Supreme and Appeals Court"' ]; then
  echo "Seems to be CSV in expected format. Checking for changes from last version."

  if test -f $LATEST_FILE; then
      echo "Checking for differences with last file..."
      new_comparison="$(csv2json -s ";" $TMPFILE | jq -c ".[]" | ndjson-map '{"vc": d.votecount, "pr": d.precinctsreporting}')"
      existing_comparison="$(csv2json -s ";" $LATEST_FILE | jq -c ".[]" | ndjson-map '{"vc": d.votecount, "pr": d.precinctsreporting}')"

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
    gzip -vc $LATEST_FILE | aws s3 cp - s3://$ELEX_S3_URL/$LATEST_FILE.gz \
    --profile $AWS_PROFILE_NAME \
    --acl public-read \
    --content-type=text/csv \
    --content-encoding gzip

    # Push timestamped to s3
    gzip -vc $LATEST_FILE | aws s3 cp - "s3://$ELEX_S3_URL/csv/versions/results-sos-statewide-$download_datetime.csv.gz" \
    --profile $AWS_PROFILE_NAME \
    --acl public-read \
    --content-type=text/csv \
    --content-encoding gzip

    # Make local timestamped file for new changed version
    cp $TMPFILE "sos/results-sos-statewide-$download_datetime.csv"


    # Check response headers
    RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $ELEX_S3_URL/$LATEST_FILE.gz)
    if [ $RESPONSE_CODE == '200' ]; then
      echo "Successfully test-retrieved 'latest' file from S3."
    else
      echo "***** WARNING WARNING WARNING: No 'latest' file could be retrieved from S3. Response code $RESPONSE_CODE *****"
    fi

    # Get first entry of uploaded json
    FIRST_ENTRY=$(curl -s --compressed $ELEX_S3_URL/$LATEST_FILE.gz | head -n 2 $TMPFILE | csv2json -s ";" | jq '.[0]')
    if [ "$(echo $FIRST_ENTRY | jq '.officename')" == '"Supreme and Appeals Court"' ]; then
      echo "$FIRST_ENTRY"
    else
      echo "***** WARNING WARNING WARNING: Test-retrieved 'latest' file does not seem to be parseable CSV in expected format. *****"
    fi
  fi
else
  echo "***** WARNING WARNING WARNING: The newest file doesn't seem to be what we'd expect from elex CSV. Taking no further action. *****"
fi
printf "\n\n"
