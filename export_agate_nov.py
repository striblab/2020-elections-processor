import re
import json
import pandas as pd
import requests
import datetime

SOS_HEADER_ROW = ["state", "county_id_sos", "precinct_id", "office_id", "seatname", "district", "cand_order", "full_name", "suffix", "incumbent", "party", "precinctsreporting", "precinctstotal", "votecount", "votepct", "votes_office"]

# https://electionresultsfiles.sos.state.mn.us/20201103/ussenate.txt

lookup = {
    'U.S. Senate': {
        'outfile_name': 'USSEN',
        'formatter': 'statewide',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/ussenate.txt'
    },
    'U.S. House': {
        'outfile_name': 'USHSE',
        'formatter': 'legis',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/ushouse.txt'
    },
    'State Senate': {
        'outfile_name': 'MNSEN',
        'formatter': 'legis',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/stsenate.txt'
    },
    'State House': {
        'outfile_name': 'MNHSE',
        'formatter': 'legis',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/LegislativeByDistrict.txt'
    },
    'Statewide courts': {
        'outfile_name': 'ELEX_MNJUD',
        'formatter': 'courts',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/judicial.txt'
    },
    'District courts': {
        'outfile_name': 'ELEX_MNJUD',
        'formatter': 'courts',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/judicialdst.txt'
    },
}

# x - ELEX_USSEN: U.S. Senate race for Minn. (Smith v. Lewis)
# x - ELEX_USHSE: U.S House races for the eight Minn. Seats
# x - ELEX_MNSEN: Minn. Senate races
# x - ELEX_MNHSE: Minn. House races
# ELES_METCO: Metro area county races
# ELEX_METCITY: Metro area city races
# ELEX_METQUES: Metro area city ballot questions
# x - ELEX_MNJUD: Judicial races (courts)
# ELEX_METSCHB: Metro area school board races
# ELEX_METSCHQ: Metro area school questions


def process_sos_csv(header_row, url, race_format):
    df = pd.read_csv(url, delimiter=";", names=header_row, encoding='latin-1').sort_values(['office_id', 'district', 'votecount'], ascending=[True, True, False]).fillna(0)
    df['race_format'] = race_format
    return df


def district_finder(input_str):
    '''Extract district name from our processed SOS json'''
    district = re.search(r'(District) (\d+)([A-z]*)', input_str)
    if district:
        # print(district.group(0))
        numeric = int(district.group(2))
        # print(numeric)
        modifier = district.group(3)
        # print(modifier)
        return district.group(0), numeric, modifier
    return input_str, None, None

def district_formatter(row):
    if row['race_format'] == 'statewide':
        row['office_name'] = row['seatname']
        row['seat_name_subhed'] = ''
        row['seat_num_numeric'] = ''

    elif row['race_format'] == 'legis':
        seat = re.search(r'(.*) District (.*)', row['seatname'])
        seat_name = None
        office_name = seat.group(1)
        seat_num = seat.group(2)
        row['office_name'] = 'District {}'.format(seat_num)
        row['seat_name_subhed'] = ''
        row['seat_num_numeric'] = ''

    elif row['race_format'] == 'courts':

        seat = re.search(r'([A-z ]+) - ([A-z \d]+) (\d+)', row['seatname'])
        seat_name = seat.group(1)
        office_name = seat.group(2)
        seat_num = int(seat.group(3))
        row['office_name'] = office_name.upper()
        row['seat_name_subhed'] = '{} - SEAT {}'.format(seat_name.upper(), seat_num)
        row['seat_num_numeric'] = seat_num
    return row


def party_formatter(party):
    if party in  [0, 'WI', 'NP']:
        return ''
    elif party in ['DFL', 'Dem']:
        return ' - D'
    elif party in ['R', 'GOP']:
        return ' - R'
    return ' - ' + party


# for officetype in ['U.S. Senate', 'U.S. House', 'State Senate', 'State House']:
for officetype in ['U.S. Senate', 'U.S. House', 'State Senate', 'State House', 'Statewide courts']:

    output = ''

    if officetype == 'Statewide courts':
        df = process_sos_csv(SOS_HEADER_ROW, lookup['Statewide courts']['sos_source_file'], 'courts')
        df = df.append(process_sos_csv(SOS_HEADER_ROW, lookup['District courts']['sos_source_file'], 'courts'))
    else:
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])

    df = df.apply(lambda x: district_formatter(x), axis=1)
    print(df[['office_name', 'seatname', 'district', 'seat_name_subhed', 'seat_num_numeric']])
    print(df.columns)

    races = {}

    for m in df.to_dict('records'):
        if m['seatname']:
            seat_name = m['seatname']
        else:
            seat_name = m['officetype']

        if seat_name not in races:
            races[seat_name] = {'cands': []}

        races[seat_name]['cands'].append(m)

    # print(races)
    prev_office_name = ''
    for k, race in races.items():

        # Ignore uncontested
        if len(race['cands']) > 2:
            # Find leader
            # candidates = sorted(race[party_cands], key=lambda i: int(i['votecount']), reverse=True)
            # if race['cands'][0]['seatname']:
            #     seat = race['cands'][0]['district_full']
            # else:
            #     seat = race['cands'][0]['officetype']

            precinctsreporting = int(race['cands'][0]['precinctsreporting'])
            precinctstotal = int(race['cands'][0]['precinctstotal'])
            precinctsreportingpct = round(100 * float(precinctsreporting / precinctstotal))

            # office_name, seat_name = district_formatter(officetype, race['cands'][0]['seatname'])
            office_name = race['cands'][0]['office_name']
            seat_name_subhed = race['cands'][0]['seat_name_subhed']
            if office_name != prev_office_name:
                output += '@Elex_Head1:{}\n'.format(office_name)
                prev_office_name = office_name

            if seat_name_subhed:
                output += '@Elex_Head2:{}\n'.format(seat_name_subhed)

            output += '@Elex_Precinct:{0} of {1} precincts ({2}%)\n'.format(f'{precinctsreporting:,}', f'{precinctstotal:,}', precinctsreportingpct)

            for k, c in enumerate(race['cands']):
                # Filter out write-ins unless they win
                if c['full_name'] == 'WRITE-IN' and k != 0:
                    pass
                else:
                    if 'full_name' in c:
                        full_name = c['full_name']
                    else:
                        full_name = '{} {}'.format(c['first'], c['last'])
                    # party = party_formatter(c['party'])
                    votes = int(c['votecount'])
                    pct = round(c['votepct'])
                    # Winner?
                    # winner = '<saxo:ch value="226 136 154"/>' if c['winner'] else ''
                    incumbent = ' (i)' if c['incumbent'] == True else ''
                    output += '@Elex_Text_2tabsPlusPct:	{}{}{}	{}	{}%\n'.format(full_name, incumbent, party_formatter(c['party']), f'{votes:,}', pct)

    print(output)
    update_time = datetime.datetime.now()
    outfile_name = 'txt/ELX_{}_{}_{}.txt'.format(lookup[officetype]['outfile_name'], update_time.strftime('%m%d%y'), update_time.strftime('%H%M'))
    print('Exporting {}'.format(outfile_name))
    with open(outfile_name, 'w') as outfile:
        outfile.write(output)
        outfile.close()

    # sos_statewide_json = 'https://static.startribune.com/elections/projects/2020-election-results/august/json/results-sos-statewide-latest.json'
    # ap_statewide_json = 'https://static.startribune.com/elections/projects/2020-election-results/august/json/results-latest.json'
    #
    # r = requests.get(ap_statewide_json)
    #
    # if r.ok:
    #     matching_results = [row for row in r.json() if row['officetype'] == officetype]
    #     races = {}
    #
    #     # Sort by district if it's present
    #     if matching_results[0]['seatname']:
    #         matching_results = [row for row in r.json() if row['officetype'] == officetype]
    #         for m in matching_results:
    #             m['district_full'], m['dist_numeric'], m['dist_modifier'] = district_finder(m['seatname'])
    #             # m['seatnum_numeric'] = re.search(r'District (\d+[])')
    #         matching_results = sorted([row for row in matching_results], key = lambda i: i['dist_numeric'])
    #
    #     for m in matching_results:
    #         if m['seatname']:
    #             seat_name = m['seatname']
    #         else:
    #             seat_name = m['officetype']
    #
    #         if seat_name not in races:
    #             races[seat_name] = {'d_cands': [], 'r_cands': []}
    #
    #         # Split into parties (for primaries)
    #         party = party_formatter(m['party'])
    #         if party == 'D':
    #             races[seat_name]['d_cands'].append(m)
    #         elif party == 'R':
    #             races[seat_name]['r_cands'].append(m)
    #
    #     for k, race in races.items():
    #         for party_cands in ['d_cands', 'r_cands']:
    #             # Ignore uncontested
    #             if len(race[party_cands]) > 1:
    #                 # Find leader
    #                 candidates = sorted(race[party_cands], key=lambda i: int(i['votecount']), reverse=True)
    #                 if candidates[0]['seatname']:
    #                     seat = candidates[0]['district_full']
    #                 else:
    #                     seat = candidates[0]['officetype']
    #
    #                 precinctsreporting = int(candidates[0]['precinctsreporting'])
    #                 precinctstotal = int(candidates[0]['precinctstotal'])
    #                 precinctsreportingpct = round(100 * float(candidates[0]['precinctsreportingpct']))
    #
    #                 output += '@Elex_Head1:{}: {}\n'.format(seat, party_formatter(candidates[0]['party']))
    #                 output += '@Elex_Precinct:{0} of {1} precincts ({2}%)\n'.format(f'{precinctsreporting:,}', f'{precinctstotal:,}', precinctsreportingpct)
    #
    #                 for c in candidates:
    #
    #                     if 'full_name' in c:
    #                         full_name = c['full_name']
    #                     else:
    #                         full_name = '{} {}'.format(c['first'], c['last'])
    #                     # party = party_formatter(c['party'])
    #                     votes = int(c['votecount'])
    #                     pct = round(100 * float(c['votepct']))
    #                     # Winner?
    #                     winner = '<saxo:ch value="226 136 154"/>' if c['winner'] else ''
    #                     incumbent = ' (i)' if c['incumbent'] else ''
    #                     output += '@Elex_Text_2tabsPlusPct:{}	{}{}	{}	{}%\n'.format(winner, full_name, incumbent, f'{votes:,}', pct)
    #
    #     # print(output)
    #     update_time = datetime.datetime.now()
    #     outfile_name = 'txt/ELX_{}_{}_{}.txt'.format(filenames[officetype], update_time.strftime('%m%d%y'), update_time.strftime('%H%M'))
    #     print('Exporting {}'.format(outfile_name))
    #     with open(outfile_name, 'w') as outfile:
    #         outfile.write(output)
    #         outfile.close()


# @Elex_Head1:District 1
# @Elex_Precinct:698 of 698 precincts (100%)
# @Elex_Text_2tabsPlusPct:	Jim Hagedorn - R	146,202	50%
# @Elex_Text_2tabsPlusPct:	Dan Feehan - D	144,891	50%
# @Elex_Head1:District 2
# @Elex_Precinct:292 of 292 precincts (100%)
# @Elex_Text_2tabsPlusPct:<saxo:ch value="226 136 154"/>	Angie Craig - D	177,971	53%
# @Elex_Text_2tabsPlusPct:	Jason Lewis (i) - R	159,373	47%

# {'officetype': 'U.S. House', 'statepostal': 'MN', 'full_name': 'Tawnja Zahradka', 'party': 'DFL', 'votecount': '0', 'votepct': '0.00', 'winner': False, 'level': 'statewide', 'precinctsreporting': '0', 'precinctstotal': '281', 'precinctsreportingpct': '0.00', 'seatname': 'U.S. Representative District 6', 'fipscode': None, 'county_id_sos': '', 'lastupdated': '2020-08-07T16:37:56'}, {'officetype': 'U.S. House', 'statepostal': 'MN', 'full_name': 'William Louwagie', 'party': 'R', 'votecount': '0', 'votepct': '0.00', 'winner': False, 'level': 'statewide', 'precinctsreporting': '0', 'precinctstotal': '1329', 'precinctsreportingpct': '0.00', 'seatname': 'U.S. Representative District 7', 'fipscode': None, 'county_id_sos': '', 'lastupdated': '2020-08-07T16:37:56'}
