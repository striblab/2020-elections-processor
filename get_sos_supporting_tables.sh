#!/bin/bash
set -o allexport; source .env; set +o allexport

# Make supporting_tables directory if it doesn't exist
[ -d supporting_tables ] || mkdir supporting_tables

echo "county_id_sos;county_name;fips_code;location_name" | \
cat - <(curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/mcdtbl.txt | iconv -f iso8859-1 -t utf-8) | csv2json -s ";" | jq -c ".[]" > supporting_tables/sos_city_lookup.ndjson

echo "school_dist_num;location_name;county_id_sos;county_name" | \
cat - <(curl -s --ftp-ssl --user media:results ftp://ftp.sos.state.mn.us/20201103/SchoolDistTbl.txt | iconv -f iso8859-1 -t utf-8) | csv2json -s ";" | jq -c ".[]" | \
  ndjson-map 'd.location_name = d.location_name + " SCHOOL DISTRICT", d' > supporting_tables/sos_school_lookup.ndjson
