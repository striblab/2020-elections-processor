import os
import sys
import pandas as pd

state_lookup_df = pd.read_json('json/state-electoral-votes-and-history.json', orient='records')
state_lookup_df.rename(columns={'abbreviation': 'statepostal', 'name': 'state'}, inplace=True)

def format_pct(raw_pct):
    pct_whole = round(100 * raw_pct, 1)
    if int(pct_whole) == 0:
        return '0%'
    elif int(pct_whole) == 100:
        return '100%'
    return '{}%'.format(pct_whole)

def format_electoral(raw_electoral):
    if raw_electoral == 0:
        return '-'
    return raw_electoral

ELECTORAL_IN_FILE = os.path.join('json', 'results-national-ap-latest.json')

all_df = pd.read_json(ELECTORAL_IN_FILE)
electoral_df = all_df[
    (all_df['officename'] == 'President')
    & (all_df['level'] == 'state')
]

trump_rows = electoral_df[electoral_df['last'] == 'Trump'][['statepostal', 'votecount', 'votepct', 'electvotes']]
trump_rows.rename(columns={'electvotes': 'trump_electoral', 'votecount': 'trump_votes', 'votepct': 'trump_pct'}, inplace=True)

biden_rows = electoral_df[electoral_df['last'] == 'Biden'][['statepostal', 'votecount', 'votepct', 'electvotes']]
biden_rows.rename(columns={'electvotes': 'biden_electoral', 'votecount': 'biden_votes', 'votepct': 'biden_pct'}, inplace=True)

state_precincts = electoral_df[['statepostal', 'precinctsreportingpct']].drop_duplicates()

merged = state_precincts.merge(
    state_lookup_df,
    how="left",
    on="statepostal"
).merge(
    trump_rows,
    how="left",
    on="statepostal"
).merge(
    biden_rows,
    how="left",
    on="statepostal"
)

biden_total = merged.biden_votes.sum()
trump_total = merged.trump_votes.sum()

biden_electoral_total = merged.biden_electoral.sum()
trump_electoral_total = merged.trump_electoral.sum()

# Format integers
merged['biden_votes'] = merged['biden_votes'].apply(lambda x: "{:,}".format(x))
merged['trump_votes'] = merged['trump_votes'].apply(lambda x: "{:,}".format(x))

# Format electoral
merged['trump_electoral'] = merged['trump_electoral'].apply(lambda x: format_electoral(x))
merged['biden_electoral'] = merged['biden_electoral'].apply(lambda x: format_electoral(x))

# Format percents
merged['biden_pct'] = merged['biden_pct'].apply(lambda x: format_pct(x))
merged['trump_pct'] = merged['trump_pct'].apply(lambda x: format_pct(x))
merged['precinct_pct'] = merged['precinctsreportingpct'].apply(lambda x: format_pct(x))

out_df = merged[[
    'state',
    'precinct_pct',
    'biden_electoral',
    'trump_electoral',
    'biden_votes',
    'biden_pct',
    'trump_votes',
    'trump_pct'
]].sort_values('state')

out_df = out_df.append({
    'state': 'Total',
    'precinct_pct': None,
    'biden_electoral': biden_electoral_total,
    'trump_electoral': trump_electoral_total,
    'biden_votes': "{:,}".format(biden_total),
    'biden_pct': None,
    'trump_votes': "{:,}".format(trump_total),
    'trump_pct': None,
}, ignore_index=True)

out_df.to_csv(sys.stdout, sep=';', index=False)
