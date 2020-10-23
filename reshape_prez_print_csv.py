import os
import sys
import requests
import pandas as pd

def get_json_from_s3(uri):
    r = requests.get(uri)
    if r.ok:
        return r.content
    return False

def format_pct(raw_pct):
    # pct_whole = round(100 * raw_pct, 1)
    # if int(pct_whole) == 0:
    #     return '0%'
    # elif int(pct_whole) == 100:
    #     return '100%'
    pct_whole = round(100 * raw_pct)
    return '{}%'.format(pct_whole)

COUNTY_IN_FILE = os.path.join('https://', os.environ.get('ELEX_S3_URL'), 'json', 'results-mn-county-latest.json')

county_df = pd.read_json(get_json_from_s3(COUNTY_IN_FILE), dtype={'fipscode': object}, orient='records')
mn_county_prez = county_df[
    (county_df['officename'] == 'President')
    & (~county_df['fipscode'].isna())
]

trump_rows = mn_county_prez[mn_county_prez['last'] == 'Trump'][['reportingunitname', 'votecount', 'votepct']]
trump_rows.rename(columns={'votecount': 'trump_votes', 'votepct': 'trump_pct'}, inplace=True)

biden_rows = mn_county_prez[mn_county_prez['last'] == 'Biden'][['reportingunitname', 'votecount', 'votepct']]
biden_rows.rename(columns={'votecount': 'biden_votes', 'votepct': 'biden_pct'}, inplace=True)

county_precincts = mn_county_prez[['reportingunitname', 'precinctsreportingpct']].drop_duplicates()

merged = county_precincts.merge(
    trump_rows,
    how="left",
    on="reportingunitname"
).merge(
    biden_rows,
    how="left",
    on="reportingunitname"
)

biden_total = merged.biden_votes.sum()
trump_total = merged.trump_votes.sum()

# Format integers
merged['biden_votes'] = merged['biden_votes'].apply(lambda x: "{:,}".format(x))
merged['trump_votes'] = merged['trump_votes'].apply(lambda x: "{:,}".format(x))

# Format percents
merged['biden_pct'] = merged['biden_pct'].apply(lambda x: format_pct(x))
merged['trump_pct'] = merged['trump_pct'].apply(lambda x: format_pct(x))
merged['precinct_pct'] = merged['precinctsreportingpct'].apply(lambda x: format_pct(x))

merged.rename(columns={'reportingunitname': 'county'}, inplace=True)

out_df = merged[[
    'county',
    'precinct_pct',
    'biden_votes',
    'biden_pct',
    'trump_votes',
    'trump_pct'
]].sort_values('county')

out_df = out_df.append({
    'county': 'Total',
    'precinct_pct': None,
    'biden_votes': "{:,}".format(biden_total),
    'biden_pct': None,
    'trump_votes': "{:,}".format(trump_total),
    'trump_pct': None,
}, ignore_index=True)

out_df.to_csv(sys.stdout, sep=';', index=False)
