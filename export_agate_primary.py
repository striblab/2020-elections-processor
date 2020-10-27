import re
import json
import requests
import datetime

# officename = 'State Senate'
# officename = 'State House'
# officename = 'U.S. Senate'
# officename = 'U.S. House'
for officename in ['U.S. Senate', 'U.S. House', 'State Senate', 'State House']:

    filenames = {
        'State Senate': 'MNSEN',
        'State House': 'MNHSE',
        'U.S. Senate': 'USSEN',
        'U.S. House': 'USHSE',
    }

    output = ''

    sos_statewide_json = 'https://static.startribune.com/elections/projects/2020-election-results/august/json/results-sos-statewide-latest.json'
    ap_statewide_json = 'https://static.startribune.com/elections/projects/2020-election-results/august/json/results-latest.json'

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

    def party_formatter(party):
        if party in ['DFL', 'Dem']:
            return 'D'
        elif party in ['R', 'GOP']:
            return 'R'
        return party

    r = requests.get(ap_statewide_json)

    if r.ok:
        matching_results = [row for row in r.json() if row['officename'] == officename]
        races = {}

        # Sort by district if it's present
        if matching_results[0]['seatname']:
            matching_results = [row for row in r.json() if row['officename'] == officename]
            for m in matching_results:
                m['district_full'], m['dist_numeric'], m['dist_modifier'] = district_finder(m['seatname'])
                # m['seatnum_numeric'] = re.search(r'District (\d+[])')
            matching_results = sorted([row for row in matching_results], key = lambda i: i['dist_numeric'])

        for m in matching_results:
            if m['seatname']:
                seat_name = m['seatname']
            else:
                seat_name = m['officename']

            if seat_name not in races:
                races[seat_name] = {'d_cands': [], 'r_cands': []}

            # Split into parties (for primaries)
            party = party_formatter(m['party'])
            if party == 'D':
                races[seat_name]['d_cands'].append(m)
            elif party == 'R':
                races[seat_name]['r_cands'].append(m)

        for k, race in races.items():
            for party_cands in ['d_cands', 'r_cands']:
                # Ignore uncontested
                if len(race[party_cands]) > 1:
                    # Find leader
                    candidates = sorted(race[party_cands], key=lambda i: int(i['votecount']), reverse=True)
                    if candidates[0]['seatname']:
                        seat = candidates[0]['district_full']
                    else:
                        seat = candidates[0]['officename']

                    precinctsreporting = int(candidates[0]['precinctsreporting'])
                    precinctstotal = int(candidates[0]['precinctstotal'])
                    precinctsreportingpct = round(100 * float(candidates[0]['precinctsreportingpct']))

                    output += '@Elex_Head1:{}: {}\n'.format(seat, party_formatter(candidates[0]['party']))
                    output += '@Elex_Precinct:{0} of {1} precincts ({2}%)\n'.format(f'{precinctsreporting:,}', f'{precinctstotal:,}', precinctsreportingpct)

                    for c in candidates:

                        if 'full_name' in c:
                            full_name = c['full_name']
                        else:
                            full_name = '{} {}'.format(c['first'], c['last'])
                        # party = party_formatter(c['party'])
                        votes = int(c['votecount'])
                        pct = round(100 * float(c['votepct']))
                        # Winner?
                        winner = '<saxo:ch value="226 136 154"/>' if c['winner'] else ''
                        incumbent = ' (i)' if c['incumbent'] else ''
                        output += '@Elex_Text_2tabsPlusPct:{}	{}{}	{}	{}%\n'.format(winner, full_name, incumbent, f'{votes:,}', pct)

        # print(output)
        update_time = datetime.datetime.now()
        outfile_name = 'txt/ELX_{}_{}_{}.txt'.format(filenames[officename], update_time.strftime('%m%d%y'), update_time.strftime('%H%M'))
        print('Exporting {}'.format(outfile_name))
        with open(outfile_name, 'w') as outfile:
            outfile.write(output)
            outfile.close()


# @Elex_Head1:District 1
# @Elex_Precinct:698 of 698 precincts (100%)
# @Elex_Text_2tabsPlusPct:	Jim Hagedorn - R	146,202	50%
# @Elex_Text_2tabsPlusPct:	Dan Feehan - D	144,891	50%
# @Elex_Head1:District 2
# @Elex_Precinct:292 of 292 precincts (100%)
# @Elex_Text_2tabsPlusPct:<saxo:ch value="226 136 154"/>	Angie Craig - D	177,971	53%
# @Elex_Text_2tabsPlusPct:	Jason Lewis (i) - R	159,373	47%

# {'officename': 'U.S. House', 'statepostal': 'MN', 'full_name': 'Tawnja Zahradka', 'party': 'DFL', 'votecount': '0', 'votepct': '0.00', 'winner': False, 'level': 'statewide', 'precinctsreporting': '0', 'precinctstotal': '281', 'precinctsreportingpct': '0.00', 'seatname': 'U.S. Representative District 6', 'fipscode': None, 'county_id_sos': '', 'lastupdated': '2020-08-07T16:37:56'}, {'officename': 'U.S. House', 'statepostal': 'MN', 'full_name': 'William Louwagie', 'party': 'R', 'votecount': '0', 'votepct': '0.00', 'winner': False, 'level': 'statewide', 'precinctsreporting': '0', 'precinctstotal': '1329', 'precinctsreportingpct': '0.00', 'seatname': 'U.S. Representative District 7', 'fipscode': None, 'county_id_sos': '', 'lastupdated': '2020-08-07T16:37:56'}
