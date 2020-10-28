import re
import json
import pandas as pd
import requests
import datetime

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
    'Metro counties': {
        'outfile_name': 'ELEX_METCO',
        'formatter': 'county',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/cntyRaceQuestions.txt'
    },
    'Metro cities': {
        'outfile_name': 'ELEX_METCITY',
        'formatter': 'city',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/local.txt'
    },
    'Metro city questions': {
        'outfile_name': 'ELEX_METQUES',
        'formatter': 'question',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/local.txt'
    },
    'Metro schools': {
        'outfile_name': 'ELEX_METSCHB',
        'formatter': 'schools',
        'sos_source_file': 'https://electionresultsfiles.sos.state.mn.us/20201103/SDRaceQuestions.txt'
    },
}

# x - ELEX_USSEN: U.S. Senate race for Minn. (Smith v. Lewis)
# x - ELEX_USHSE: U.S House races for the eight Minn. Seats
# x - ELEX_MNSEN: Minn. Senate races
# x - ELEX_MNHSE: Minn. House races
# x - ELES_METCO: Metro area county races
# x - ELEX_METCITY: Metro area city races
# x - ELEX_MNJUD: Judicial races (courts)
# x - ELEX_METQUES: Metro area city ballot questions
# x - ELEX_METSCHB: Metro area school board races
# ELEX_METSCHQ: Metro area school questions

SOS_HEADER_ROW = ["state", "county_id_sos", "precinct_id", "office_id", "seatname", "district", "cand_order", "full_name", "suffix", "incumbent", "party", "precinctsreporting", "precinctstotal", "votecount", "votepct", "votes_office"]

SOS_CITY_LOOKUP_HEADER_ROW = ["county_id_sos", "county_name", "fips_code", "location_name"]

SOS_SCHOOLS_LOOKUP_HEADER_ROW = ["school_dist_num", "location_name", "county_id_sos", "county_name"]

SOS_QUES_LOOKUP_HEADER_ROW = ["county_id_sos", "office_id", "fips_code", "school_dist_num", "question_num", "question_title", "question_body"]

COUNTY_LOOKUP = {
    '02': 'Anoka',
    '10': 'Carver',
    '19': 'Dakota',
    '27': 'Hennepin',
    '62': 'Ramsey',
    '70': 'Scott',
    '82': 'Washington',
}

city_lookup = pd.read_csv(
    'https://electionresultsfiles.sos.state.mn.us/20201103/mcdtbl.txt',
    delimiter=";", names=SOS_CITY_LOOKUP_HEADER_ROW, encoding='latin-1', dtype='object'
)

school_lookup = pd.read_csv(
    'https://electionresultsfiles.sos.state.mn.us/20201103/SchoolDistTbl.txt',
    delimiter=";", names=SOS_SCHOOLS_LOOKUP_HEADER_ROW, encoding='latin-1', dtype='object'
)

def process_sos_csv(header_row, url, race_format):
    df = pd.read_csv(url, delimiter=";", names=header_row, encoding='latin-1', dtype={'county_id_sos': 'object', 'office_id': 'object', 'district': 'object'}).sort_values(['office_id', 'district', 'votecount'], ascending=[True, True, False]).fillna(0)
    df['office_id_strib'] = df['county_id_sos'].astype(str) + df['office_id'].astype(str) + df['district'].astype(str)
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
        row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'legis':
        seat = re.search(r'(.*) District (.*)', row['seatname'])
        seat_name = None
        office_name = seat.group(1)
        seat_num = seat.group(2)
        row['office_name'] = 'District {}'.format(seat_num)
        row['seat_name_subhed'] = ''
        row['seat_num_numeric'] = ''
        row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'county':
        row['office_name'] = row['location_name'].upper() + ' COUNTY'
        row['seat_name_subhed'] = row['seatname'].upper().replace('COUNTY ', '').replace('SOIL AND WATER SUPERVISOR DISTRICT', 'SOIL AND WATER SUPERVISOR')
        row['seat_num_numeric'] = ''
        row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'city':
        seat = re.search(r'([A-z. \d]+) \(([A-z. #\d]+)\)(?: \(Elect (\d+)\))?', row['seatname'])
        # location_name = seat.group(2)
        seat_name = seat.group(1)
        row['office_name'] = row['location_name'].upper()
        row['seat_name_subhed'] = seat_name.upper().replace('COUNCIL MEMBER', 'CITY COUNCIL').replace('SPECIAL ELECTION FOR', 'SPECIAL: ')
        row['seat_num_numeric'] = ''
        if seat.group(3):
            row['num_seats'] = 'Open seats: {}'.format(seat.group(3))
        else:
            row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'schools':
        seat = re.search(r'([A-z. \d]+) \(([A-z. #\d]+)\)(?: \(Elect (\d+)\))?', row['seatname'])
        # location_name = seat.group(2)
        seat_name = seat.group(1)
        row['office_name'] = row['location_name'].upper()
        if seat_name == 'School Board Member':
            row['seat_name_subhed'] = ''
        elif seat_name == 'School Board Member at Large':
            row['seat_name_subhed'] = 'AT LARGE'
        elif seat_name == 'Special Election for School Board Member':
            row['seat_name_subhed'] = 'SPECIAL'
        else:
            row['seat_name_subhed'] = seat_name.replace('School Board Member', '').replace('Special Election for ', 'SPECIAL:').upper().strip()
        row['seat_num_numeric'] = ''
        if seat.group(3):
            row['num_seats'] = 'Open seats: {}'.format(seat.group(3))
        else:
            row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'courts':
        seat = re.search(r'([A-z ]+) - ([A-z \d]+) (\d+)', row['seatname'])
        seat_name = seat.group(1)
        office_name = seat.group(2)
        seat_num = int(seat.group(3))
        row['office_name'] = office_name.upper()
        row['seat_name_subhed'] = '{} - SEAT {}'.format(seat_name.upper(), seat_num)
        row['seat_num_numeric'] = seat_num
        row['num_seats'] = ''
        row['question_strib'] = ''

    elif row['race_format'] == 'question':
        office_name = row['location_name'].upper()
        row['office_name'] = row['location_name'].upper()
        row['seat_name_subhed'] = ''
        row['seat_num_numeric'] = ''
        row['num_seats'] = ''
        question_num = re.search(r'QUESTION (\d+)', row['question_num'])
        row['question_strib'] = 'Question {}: {}'.format(question_num.group(1), row['question_body'].replace('^', ';'))
    return row


def party_formatter(party):
    if party in  [0, 'WI', 'NP']:
        return ''
    elif party in ['DFL', 'Dem']:
        return ' - D'
    elif party in ['R', 'GOP']:
        return ' - R'
    return ' - ' + party


# for officetype in ['U.S. Senate', 'U.S. House', 'State Senate', 'State House', 'Statewide courts', 'Metro counties', 'Metro cities', 'Metro city questions']:
for officetype in ['Metro schools']:

    output = ''

    if officetype == 'Statewide courts':
        df = process_sos_csv(SOS_HEADER_ROW, lookup['Statewide courts']['sos_source_file'], 'courts')
        df = df.append(process_sos_csv(SOS_HEADER_ROW, lookup['District courts']['sos_source_file'], 'courts'))
    elif lookup[officetype]['formatter'] == 'county':
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])
        df = df[df['county_id_sos'].isin(COUNTY_LOOKUP.keys())]
        df['location_name'] = df['county_id_sos'].apply(lambda x: COUNTY_LOOKUP[x])
        df = df.sort_values(['location_name', 'office_id', 'district', 'votecount'], ascending=[True, True, True, False])

    elif lookup[officetype]['formatter'] == 'city':
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])
        df = df[~df['seatname'].str.contains('QUESTION')] # Remove questions (Do separately)

        df = df.drop(columns=['county_id_sos']).merge(
            city_lookup,
            how="left",
            left_on="district",
            right_on="fips_code"
        )

        df = df[df['county_id_sos'].isin(COUNTY_LOOKUP.keys())].drop(columns=['county_id_sos', 'county_name']).drop_duplicates()
        df['location_name'] = df['location_name'].str.replace('City of ', '')  # remove "city of" before sorting
        df = df.sort_values(['location_name', 'office_id', 'district', 'votecount'], ascending=[True, True, True, False])

    elif lookup[officetype]['formatter'] == 'schools':
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])
        df = df[~df['seatname'].str.contains('QUESTION')] # Remove questions (Do separately)

        df = df.drop(columns=['county_id_sos']).merge(
            school_lookup,
            how="left",
            left_on="district",
            right_on="school_dist_num"
        )

        df = df[df['county_id_sos'].isin(COUNTY_LOOKUP.keys())].drop(columns=['county_id_sos', 'county_name']).drop_duplicates()
        # df['location_name'] = df['location_name'].str.replace('City of ', '')  # remove "city of" before sorting
        df = df.sort_values(['location_name', 'office_id', 'district', 'votecount'], ascending=[True, True, True, False])

    elif lookup[officetype]['formatter'] == 'question':
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])
        df = df[df['seatname'].str.contains('QUESTION')]

        df = df.drop(columns=['county_id_sos']).merge(
            city_lookup,
            how="left",
            left_on="district",
            right_on="fips_code"
        )
        df['lookup'] = df['fips_code'].astype(str) + df['office_id'].astype(str)

        df = df[df['county_id_sos'].isin(COUNTY_LOOKUP.keys())].drop(columns=['county_id_sos', 'county_name']).drop_duplicates()
        df['location_name'] = df['location_name'].str.replace('City of ', '')  # remove "city of" before sorting

        ques_lookup = pd.read_csv(
            'https://electionresultsfiles.sos.state.mn.us/20201103/BallotQuestions.txt',
            delimiter=";", names=SOS_QUES_LOOKUP_HEADER_ROW, encoding='latin-1', dtype={'county_id_sos': 'object', 'office_id': 'object', 'fips_code': 'object'}
        )

        ques_lookup['lookup'] = ques_lookup['fips_code'].astype(str) + ques_lookup['office_id'].astype(str)
        df = df.drop(columns=['office_id']).merge(
            ques_lookup,
            how="left",
            on="lookup"
        )

        df = df.sort_values(['location_name', 'office_id', 'district', 'full_name'], ascending=[True, True, True, False])  # Put yes first (seatname) rather than leader

    else:
        df = process_sos_csv(SOS_HEADER_ROW, lookup[officetype]['sos_source_file'], lookup[officetype]['formatter'])

    df = df.apply(lambda x: district_formatter(x), axis=1)
    print(df)
    # print(df[['office_name', 'seatname', 'district', 'seat_name_subhed', 'seat_num_numeric']])

    races = {}

    for m in df.to_dict('records'):
        # if m['seatname']:
        #     seat_name = m['seatname']
        # else:
        #     seat_name = m['officetype']

        if m['office_id_strib'] not in races:
            races[m['office_id_strib']] = {'cands': []}

        # Filter out write-ins unless they are winning
        if m['full_name'] == 'WRITE-IN' and len(races[m['office_id_strib']]['cands']) != 0:
            pass
        else:
            races[m['office_id_strib']]['cands'].append(m)

    # print(races)
    prev_office_name = ''
    for k, race in races.items():

        # Ignore uncontested.
        if len(race['cands']) > 1:
            precinctsreporting = int(race['cands'][0]['precinctsreporting'])
            precinctstotal = int(race['cands'][0]['precinctstotal'])
            precinctsreportingpct = round(100 * float(precinctsreporting / precinctstotal))

            office_name = race['cands'][0]['office_name']
            seat_name_subhed = race['cands'][0]['seat_name_subhed']
            num_seats = race['cands'][0]['num_seats']
            question_strib = race['cands'][0]['question_strib']

            if office_name != prev_office_name:
                output += '@Elex_Head1:{}\n'.format(office_name)
                prev_office_name = office_name

            if seat_name_subhed:
                output += '@Elex_Head2:{}\n'.format(seat_name_subhed)

            if question_strib:
                output += '@Elex_Text_Question:{}\n'.format(question_strib)

            if num_seats != '':
                output += '@Elex_Precinct:{}\n'.format(num_seats)

            output += '@Elex_Precinct:{0} of {1} precincts ({2}%)\n'.format(f'{precinctsreporting:,}', f'{precinctstotal:,}', precinctsreportingpct)

            for k, c in enumerate(race['cands']):

                if 'full_name' in c:
                    if c['full_name'] == 'YES':
                        full_name = 'Yes'
                    elif c['full_name'] == 'NO':
                        full_name = 'No'
                    else:
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
