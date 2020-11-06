#!/bin/bash
set -o allexport; source .env; set +o allexport

  # ndjson-filter 'd.fipscode.startsWith("02")'

Getting vote totals and joining to county names
$ELEX_INSTALLATION_PREFIX/elex results 2020-11-03 -o json --results-level ru --officeids P | \
  jq -c ".[]" | \
  ndjson-filter 'd.level === "county" && d.officename === "President" && ["Biden", "Trump"].indexOf(d.last) != -1' | \
  ndjson-reduce '(p[d.fipscode] = p[d.fipscode] || []).push({name: d.last, votecount: d.votecount, votepct: d.votepct, bool_winner: d.winner}), p' '{}' | \
  ndjson-split 'Object.keys(d).map(key => ({fipscode: key, votes: d[key]}))' | \
  ndjson-map '{"fipscode": d.fipscode, "votes": d.votes.filter(obj => obj.name != "").sort((a, b) => b.bool_winner - a.bool_winner).sort((a, b) => b.votecount - a.votecount)}' | \
  ndjson-map 'd.leader = d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount ? d.votes[0].name : "even", d' | \
  ndjson-map 'd.winner_or_leading = d.votes[0].bool_winner == true ? d.votes[0].name + "_winner"  : d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount && d.votes[0].bool_winner == false ? d.votes[0].name + "_leader" : "even", d' | \
  ndjson-map 'd.winner_margin = d.votes[0].votepct - d.votes[1].votepct, d' | \
  ndjson-map 'd.leader_w_margin = d.votes.every(o => o.votecount == 0) ? "no-votes" : d.winner_margin <= 0 ? "even" : d.winner_margin < 0.1 ? d.votes[0].name + "_narrow" : d.winner_margin < 0.25 ? d.votes[0].name + "_mid" : d.winner_margin >= 0.25 ? d.votes[0].name + "_wide": "", d' > spatial/prez_county_winners_2020.tmp.ndjson


# Joining winners to US topojson
ndjson-split 'd.objects.counties.geometries' < spatial/counties-albers-10m.json | \
  ndjson-map '{"id": d.id, "type": d.type, "arcs": d.arcs, "properties": {"name": d.properties.name}}' | \
  ndjson-join --right 'd.id' 'd.fipscode' - spatial/prez_county_winners_2020.tmp.ndjson | \
  ndjson-filter 'd[0] != null' | \
  ndjson-map '{"type": d[0].type, "arcs": d[0].arcs, "properties": {"name": d[0].properties.name, "leader": d[1].leader, "winner_or_leading": d[1].winner_or_leading, "winner_margin": d[1].winner_margin, "leader_w_margin": d[1].leader_w_margin}}' | \
  ndjson-reduce 'p.geometries.push(d), p' '{"type": "GeometryCollection", "geometries":[]}' | \
  ndjson-join '1' '1' <(ndjson-cat spatial/counties-albers-10m.json) - | \
  ndjson-map '{"type": d[0].type, "bbox": d[0].bbox, "transform": d[0].transform, "objects": {"counties": {"type": "GeometryCollection", "geometries": d[1].geometries}}, "arcs": d[0].arcs}'  > spatial/counties-popular-final-topo.json

# Converting to geojson and flipping
topo2geo counties=- < spatial/counties-popular-final-topo.json | \
  geoproject 'd3.geoIdentity().reflectY(true)' > spatial/counties-popular-final-geo.json

# Colorizing SVG with margin of victory dilineated
mapshaper spatial/counties-popular-final-geo.json \
  -quiet \
  -colorizer name=calcFill colors='#115E9B,#88BBFF,#BCEDFF,#AE191C,#FF8470,#FFB59F,#CFCFCF,#AB8AA7' nodata='#F0F0F0' categories='Biden_wide,Biden_mid,Biden_narrow,Trump_wide,Trump_mid,Trump_narrow,no-votes,even' \
  -style fill='calcFill(leader_w_margin)' \
  -o id-field=name format=svg spatial/mn_2020_general_prez_counties_popular.svg

#
# Colorizing SVG with only leader
# mapshaper spatial/counties-popular-final-geo.json \
#   -quiet \
#   -colorizer name=calcFill colors='#115E9B,#AE191C,#F0F0F0,#E7E7E7' nodata='#F0F0F0' categories='Biden,Trump,no-votes,even' \
#   -style fill='calcFill(leader)' \
#   -o id-field=name format=svg spatial/mn_2020_general_prez_counties_popular.svg

# Make a blank state boundaries one too
topo2geo states=- < spatial/states-albers-10m.json | \
  geoproject 'd3.geoIdentity().reflectY(true)' | \
  mapshaper - \
    -quiet \
    -o id-field=name format=svg spatial/us_states.svg
