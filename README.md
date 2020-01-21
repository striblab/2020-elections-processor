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

AWS_PROFILE_NAME='default'
export AWS_PROFILE_NAME
```

## Running locally
To run locally, it's best to use pipenv. For production, keep reading. To set the script up with pipenv:

```bash
pipenv install
pipenv run ./get_latest_results.sh
```

### Requirements (Besides what's in the Pipfile)
Pipenv
jc

## Running in production
So far, getting pipenv to work with crontab seems like a tricky thing. And the only Python thing in this whole script is elex. So for now, I have installed elex globally with pip, then source the .env variables kinda manually at the top of the .sh file.

So...
```bash
sudo pip install elex
cd /path/to/2020-elections-processor && ./get_latest_results.sh
```
