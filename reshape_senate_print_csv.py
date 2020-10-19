import os
import sys
import pandas as pd

def format_pct(raw_pct):
    pct_whole = round(100 * raw_pct, 1)
    if int(pct_whole) == 0:
        return '0%'
    elif int(pct_whole) == 100:
        return '100%'
    return '{}%'.format(pct_whole)

COUNTY_IN_FILE = os.path.join('json', 'results-mn-county-latest.json')

county_df = pd.read_json(COUNTY_IN_FILE, dtype={'fipscode': object})
mn_county_senate = county_df[
    (county_df['officename'] == 'U.S. Senate')
    & (~county_df['fipscode'].isna())
]

lewis_rows = mn_county_senate[mn_county_senate['last'] == 'Lewis'][['reportingunitname', 'votecount', 'votepct']]
lewis_rows.rename(columns={'votecount': 'lewis_votes', 'votepct': 'lewis_pct'}, inplace=True)

smith_rows = mn_county_senate[mn_county_senate['last'] == 'Smith'][['reportingunitname', 'votecount', 'votepct']]
smith_rows.rename(columns={'votecount': 'smith_votes', 'votepct': 'smith_pct'}, inplace=True)

county_precincts = mn_county_senate[['reportingunitname', 'precinctsreportingpct']].drop_duplicates()

merged = county_precincts.merge(
    lewis_rows,
    how="left",
    on="reportingunitname"
).merge(
    smith_rows,
    how="left",
    on="reportingunitname"
)

smith_total = merged.smith_votes.sum()
lewis_total = merged.lewis_votes.sum()

# Format integers
merged['smith_votes'] = merged['smith_votes'].apply(lambda x: "{:,}".format(x))
merged['lewis_votes'] = merged['lewis_votes'].apply(lambda x: "{:,}".format(x))

# Format percents
merged['smith_pct'] = merged['smith_pct'].apply(lambda x: format_pct(x))
merged['lewis_pct'] = merged['lewis_pct'].apply(lambda x: format_pct(x))
merged['precinct_pct'] = merged['precinctsreportingpct'].apply(lambda x: format_pct(x))

merged.rename(columns={'reportingunitname': 'county'}, inplace=True)

out_df = merged[[
    'county',
    'precinct_pct',
    'smith_votes',
    'smith_pct',
    'lewis_votes',
    'lewis_pct'
]].sort_values('county')

out_df = out_df.append({
    'county': 'Total',
    'precinct_pct': None,
    'smith_votes': "{:,}".format(smith_total),
    'smith_pct': None,
    'lewis_votes': "{:,}".format(lewis_total),
    'lewis_pct': None,
}, ignore_index=True)

out_df.to_csv(sys.stdout, sep=';', index=False)
