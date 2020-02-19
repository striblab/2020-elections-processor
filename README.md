# 2020-elections-processor
Data processing scripts using elex to grab and post AP election results

This is version 1.0, which is very simple. It pulls the latest results from the AP API using elex.

It compares the current version with our existing "latest" file, and if it's different, it uploads a new "latest" file.

That's it.

## Required .env variables
To avoid committing secrets to the repo, you'll need to add a .env file, with the following set:
```
AP_API_KEY=YOUR_API_KEY
export API_API_KEY

ELEX_S3_URL=YOUR_BUCKET
export ELEX_S3_URL

# This is really annoying but currently needed so it can be changed in production because python 3 is not the default on the EC2 box.
ELEX_INSTALLATION_PREFIX='/Users/Coreymj/.local/share/virtualenvs/2020-elections-processor-4MCptR18/bin'
export ELEX_INSTALLATION_PREFIX

AWS_PROFILE_NAME='default'
export AWS_PROFILE_NAME
```

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
