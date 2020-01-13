# 2020-elections-processor
Data processing scripts using elex to grab and post AP election results

This is version 1.0, which is very simple. It pulls the latest results from the AP API using elex.

It compares the current version with our existing "latest" file, and if it's different, it uploads a new "latest" file.

That's it.

Just run:

```bash
./get_latest_results.sh
```

### Requirements (Besides what's in the Pipfile)
Pipenv
jc
