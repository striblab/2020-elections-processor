#!/bin/bash
set -o allexport; source .env; set +o allexport

# Make supporting_tables directory if it doesn't exist
[ -d supporting_tables ] || mkdir supporting_tables

# # City table
# CURL_RESPONSE=$(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/mcdtbl.txt)
#
# if [ "${#CURL_RESPONSE}" -gt "100" ]; then
#   echo "Got long response, proceeding..."
#   echo -e "county_id_sos;county_name;fips_code;location_name\n$CURL_RESPONSE" | \
#   iconv -f iso8859-1 -t utf-8 | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" > supporting_tables/sos_city_lookup.ndjson
# else
#   echo "WARNING: very short file..."
# fi
#
#
# # School district table
# CURL_RESPONSE=$(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/SchoolDistTbl.txt)
#
# if [ "${#CURL_RESPONSE}" -gt "100" ]; then
#   echo "Got long response, proceeding..."
#   echo -e "school_dist_num;location_name;county_id_sos;county_name\n$CURL_RESPONSE" | \
#   iconv -f iso8859-1 -t utf-8 | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" > supporting_tables/sos_school_lookup.ndjson
# else
#   echo "WARNING: very short file..."
# fi

# Ballot questions
CURL_RESPONSE=$(curl -s $ALLOW_INSECURE --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/BallotQuestions.txt)

if [ "${#CURL_RESPONSE}" -gt "100" ]; then
  echo "Got long response, proceeding..."
  echo -e "county_id_sos;office_id;mcd_fips;school_dist_num;question_num;question_title;question_body\n$CURL_RESPONSE" | \
  iconv -f iso8859-1 -t utf-8 | sed 's/\"/@@/g' | csv2json -s ";" | sed 's/@@/\\"/g' | jq -c ".[]" | \
    ndjson-map 'd.lookup = (d.county_id_sos + d.office_id + d.school_dist_num), d' | \
    ndjson-reduce 'p.push(d), p' '[]' > supporting_tables/sos_questions_lookup.json
    # ndjson-reduce 'p[d.lookup] = d, p' '{}' > supporting_tables/sos_questions_lookup.json
else
  echo "WARNING: very short file..."
fi
