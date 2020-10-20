#!/bin/bash
set -o allexport; source .env; set +o allexport

version_datetime=$(date '+%Y%m%d-%H-%M');
# Make print directory if it doesn't exist
[ -d print ] || mkdir print



TOPLINE_TXT_FILE=results-mn-topline-print_$version_datetime.txt
python reshape_topline_nums_print_txt.py > print/$TOPLINE_TXT_FILE

aws s3 cp print/$TOPLINE_TXT_FILE "s3://$S3_PRINT_BUCKET/$version_datetime/$TOPLINE_TXT_FILE" \
--profile $PRINT_AWS_PROFILE_NAME \
--acl public-read \
--content-type=text/plain



PREZ_ELECTORAL_FILE=results-mn-prez-electoral-print_$version_datetime.csv
python reshape_prez_electoral_print_csv.py > print/$PREZ_ELECTORAL_FILE

aws s3 cp print/$PREZ_ELECTORAL_FILE "s3://$S3_PRINT_BUCKET/$version_datetime/$PREZ_ELECTORAL_FILE" \
--profile $PRINT_AWS_PROFILE_NAME \
--acl public-read \
--content-type=text/csv



PREZ_ELECTORAL_MAP=results-mn-prez-electoral-print_$version_datetime.svg
./build_electoral_map_print.sh > print/$PREZ_ELECTORAL_MAP

aws s3 cp print/$PREZ_ELECTORAL_MAP "s3://$S3_PRINT_BUCKET/$version_datetime/$PREZ_ELECTORAL_MAP" \
--profile $PRINT_AWS_PROFILE_NAME \
--acl public-read \
--content-type=image/svg+xml



PREZ_BY_COUNTY_FILE=results-mn-prez-county-print_$version_datetime.csv
python reshape_prez_print_csv.py > print/$PREZ_BY_COUNTY_FILE

aws s3 cp print/$PREZ_BY_COUNTY_FILE "s3://$S3_PRINT_BUCKET/$version_datetime/$PREZ_BY_COUNTY_FILE" \
--profile $PRINT_AWS_PROFILE_NAME \
--acl public-read \
--content-type=text/csv



SENATE_BY_COUNTY_FILE=results-mn-ussenate-county-print_$version_datetime.csv
python reshape_senate_print_csv.py > print/$SENATE_BY_COUNTY_FILE

aws s3 cp print/$SENATE_BY_COUNTY_FILE "s3://$S3_PRINT_BUCKET/$version_datetime/$SENATE_BY_COUNTY_FILE" \
--profile $PRINT_AWS_PROFILE_NAME \
--acl public-read \
--content-type=text/csv
