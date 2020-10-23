import os
import sys
import pytz
import datetime
import requests
# from dateutil import tz
import pandas as pd

local_timezone = pytz.timezone("US/Central")


def get_json_from_s3(uri):
    r = requests.get(uri)
    if r.ok:
        return r.content
    return False

def format_pct(raw_pct):
    pct_whole = round(100 * raw_pct, 1)
    if int(pct_whole) == 0:
        return '0%'
    elif int(pct_whole) == 100:
        return '100%'
    return '{}%'.format(pct_whole)

def process_date(raw_date):
    last_updated = datetime.datetime.strptime(raw_date, '%Y-%m-%dT%H:%M:%S.%fZ')
    last_updated_utc = pytz.utc.localize(last_updated)
    last_updated_central = last_updated_utc.astimezone(local_timezone).strftime('%b %e, %I:%M %p')
    return last_updated_central
#
# def format_electoral(raw_electoral):
#     if raw_electoral == 0:
#         return '-'
#     return raw_electoral

NATIONAL_IN_FILE = os.path.join('https://', os.environ.get('ELEX_S3_URL'), 'json', 'results-national-ap-latest.json')
STATE_IN_FILE = os.path.join('https://', os.environ.get('ELEX_S3_URL'), 'json', 'results-statewide-ap-latest.json')

all_df = pd.read_json(get_json_from_s3(NATIONAL_IN_FILE), orient='records')

electoral_df = all_df[
    (all_df['officename'] == 'President')
    & (all_df['level'] == 'national')
    & (all_df['last'].isin(['Biden', 'Trump']))
]

### President ###
print('PRESIDENT')
print('Last updated by AP: {}\n'.format(process_date(electoral_df['lastupdated'].iloc[0])))

for rownum, cand in electoral_df.iterrows():
    print('{}:'.format(cand['last']))
    print('Electoral votes: {}'.format(cand['electvotes']))
    print('Popular votes: {}'.format("{:,}".format(cand['votecount'])))
    print('Popular pct: {}\n'.format(format_pct(cand['votepct'])))


### US Senate ###
senate_idle = pd.DataFrame([
    {'party': 'Dem','idle_seats': 33},
    {'party': 'GOP', 'idle_seats': 30},
    {'party': 'Ind', 'idle_seats': 2}
])

senate_races = all_df[
    (all_df['officename'] == 'U.S. Senate')
    & (all_df['level'] == 'state')
    # & (all_df['winner'] == True)
]
senate_counts = senate_races[senate_races['winner'] == True][[
    'party', 'lastupdated'
]].groupby('party').agg('count').reset_index().rename(columns={'lastupdated': 'winners'})

senate_merged = senate_counts.merge(
    senate_idle,
    how="right",
    on="party"
)
senate_merged.fillna(0, inplace=True)
senate_merged['total'] = senate_merged.winners + senate_merged.idle_seats

print('\n\nU.S. SENATE')
print('Last updated by AP: {}\n'.format(process_date(senate_races['lastupdated'].max())))
for rownum, party in senate_merged.iterrows():
    print('{}: {}'.format(party['party'], int(party['total'])))


### US House ###
house_races = all_df[
    (all_df['officename'] == 'U.S. House')
    & (all_df['level'] == 'state')
    # & (all_df['winner'] == True)
]
house_counts = house_races[house_races['winner'] == True][['party', 'lastupdated']].groupby('party').agg('count').reset_index()

print('\n\nU.S. HOUSE')
print('Last updated by AP: {}\n'.format(process_date(house_races['lastupdated'].max())))

if house_counts.shape[0] == 0:
    print('No winners called yet')
else:
    for rownum, party in house_counts.iterrows():
        print('{}: {}'.format(party['party'], party['lastupdated']))


mn_df = pd.read_json(get_json_from_s3(STATE_IN_FILE), orient='records')

### MN Senate ###
mnsen_races = mn_df[
    (mn_df['officename'] == 'State Senate')
    # & (mn_df['winner'] == True)
]
mnsen_counts = mnsen_races[mnsen_races['winner'] == True][['party', 'lastupdated']].groupby('party').agg('count').reset_index()

print('\n\nMinnesota State Senate')
print('Last updated by AP: {}\n'.format(process_date(mnsen_races['lastupdated'].max())))

if mnsen_counts.shape[0] == 0:
    print('No winners called yet')
else:
    for rownum, party in mnsen_counts.iterrows():
        print('{}: {}'.format(party['party'], party['lastupdated']))


### MN House ###
mnhouse_races = mn_df[
    (mn_df['officename'] == 'State House')
    # & (mn_df['winner'] == True)
]
mnhouse_counts = mnhouse_races[mnhouse_races['winner'] == True][['party', 'lastupdated']].groupby('party').agg('count').reset_index()

print('\n\nMinnesota State House')
print('Last updated by AP: {}\n'.format(process_date(mnhouse_races['lastupdated'].max())))

if mnhouse_counts.shape[0] == 0:
    print('No winners called yet')
else:
    for rownum, party in mnhouse_counts.iterrows():
        print('{}: {}'.format(party['party'], party['lastupdated']))
