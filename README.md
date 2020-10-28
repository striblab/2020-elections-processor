
# Components of the 2020 general election backend rig

1. [Main AP/SOS scraper](#Main-AP/SOS-scraper)
1. [Live print exporter](#Live-print-exporter)
1. Agate scripts
1. [SOS presidential precincts scraper](https://github.com/striblab/2020-sos-scraper)


## Main AP/SOS scraper

The main scraper for election night national and local results. That's this repository, `2020-elections-processor`.

Requirements:
 - Node, ideally using NVM for best results with crons
 - Python 3.7, ideally using Pyenv
 - Pipenv (Python requirements handled in the Pipfile)
 - Elex, installed from a fork at the moment that is in the Pipfile due to version constraints
 - curl (installed with Homebrew or apt)
 - jq (installed with Homebrew or apt)
 - ndjson-client (installed globally)
 - csv2json (installed globally)
 - json2csv (installed globally)
 - topo2geo (installed globally)
 - mapshaper (installed globally)
 - geoproject (installed globally)

Sample installation on Mac:
```
pyenv install 3.7
brew install curl jq
(cd to project directory)
Pipenv install
npm install -g ndjson-client csv2json json2csv topo2geo mapshaper geoproject
```

An .env file with the following settings:
```
# Use for national races
AP_API_KEY=blah
export API_API_KEY

# Use for state
AP_API_KEY_STATE_LEVEL=blah
export AP_API_KEY_STATE_LEVEL

ELEX_S3_URL=static.startribune.com/elections/projects/2020-election-results/nov
# ELEX_S3_URL=static.startribune.com/staging/news/projects/all/2020-election-results/nov
export ELEX_S3_URL

# This is really annoying but currently needed so it can be changed in production
ELEX_INSTALLATION_PREFIX='/Users/Coreymj/.local/share/virtualenvs/2020-elections-processor-4MCptR18/bin'
export ELEX_INSTALLATION_PREFIX

AWS_PROFILE_NAME='default'
export AWS_PROFILE_NAME

PRINT_AWS_PROFILE_NAME='striblab'
export PRINT_AWS_PROFILE_NAME

S3_PRINT_BUCKET=elections-print
export S3_PRINT_BUCKET

PYTHON_LOCATION='/Users/Coreymj/.local/share/virtualenvs/2020-elections-processor-4MCptR18/bin'
export PYTHON_LOCATION

PROJECT_ROOT='/Users/Coreymj/Documents/Election2020/2020-elections-processor'
export PROJECT_ROOT

# For some reason on EC2 box having trouble with ssl certs. Not great, but not sure we have an easy fix
ALLOW_INSECURE=-k
# ALLOW_INSECURE=''
export ALLOW_INSECURE

# sed on Mac in place needs a backup parameter
SED_SUFFIX=.bak
export SED_SUFFIX

```


The important scripts:

### ./run_live_results_ap.sh

This runs 4 scripts to pull national, state and county results from AP, plus statewide results from SOS, with delays between each. This is the only script you should really need to run, but it in turn runs these scripts:

#### get_latest_results_ap_national.sh
Presidential and Congressional races nationwide

#### get_latest_results_ap_statewide.sh
MN State House and State Senate results. Also includes Supreme/Appeals Court races, but we're handling those on the local page using SOS data to be consistent.

#### get_latest_results_ap_county.sh
Presidential and U.S. Senate races by MN county

#### get_latest_results_sos_summary_with_joins.sh
Grabs FTP text file results from SOS. Runs every 5 cycles to conform to SOS 500 requests per hour limit.

#### get_sos_supporting_tables.sh
Needs to be run once to get local versions of lookup tables for municipalities, school districts and question texts.

## Live print exporter
These scripts are also part of this repository. Their requirements are included in those listed above. The main script is:

### ./push_print_versions.sh

This grabs results from the AP feeds on s3, not on your local machine. The bucket it looks in and the bucket it pushes to are controlled by the .env file. It's designed to be run by crontab every 15 minutes.

Example cron line: `*/15 * * * * source /home/user/.bash_profile; cd /Users/Coreymj/Documents/Election2020/2020-elections-processor; bash -l ./push_print_versions.sh >> /Users/Coreymj/Documents/Election2020/2020-elections-processor/printlog.log 2>&1`

Note: Make sure your crontab has `SHELL=/bin/bash` set at the top.



## Old directions, could be helpful in a pinch...

## Running locally
To run locally, it's best to use pipenv. For production, keep reading. To set the script up with pipenv:

```bash
pipenv install
```

To run the results one time
```
pipenv run ./get_latest_results.sh
```

To run on 20-second cycle on an election night
```
pipenv run ./run_live_results.sh
```

### Local requirements (Besides what's in the Pipfile)
Pipenv
jc
d3
d3-geo-projection
topojson-client
ndjson
mapshaper
json2csv

## Running in production
So far, getting pipenv to work with crontab seems like a tricky thing. And the only Python thing in this whole script is elex. So for now, I have installed elex globally with pip, then source the .env variables kinda manually at the top of the .sh file.

To duplicate that install on the server in case of emergency:
```bash
sudo pip install elex awscli
```

To pull the results once:
```bash
cd apps/2020-elections-processor && ./get_latest_results.sh
```

To run on 20-second cycle on an election night, you'll want to use a screen session so you can come back and monitor/shut down/restart the process if you lose connection.
```bash
# First, ssh to the box...
# Then, to start a new screen session:
screen
# Hit enter
cd apps/2020-elections-processor
./run_live_results.sh

# To log out but keep the screen session alive gracefully
[While holding down control, press A, press D]

# If you got disconnected or the script is already running in a screen session
screen -r
# And you're back
``
