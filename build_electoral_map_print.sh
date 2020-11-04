#!/bin/bash
set -o allexport; source .env; set +o allexport

# Getting vote totals and joining to state names
# cat json/results-national-ap-latest.json | \
cat <(curl -s $ELEX_S3_URL/json/results-national-ap-latest.json) | \
  jq -c ".[]" | \
  ndjson-filter 'd.level === "state" && d.officename === "President" && ["Biden", "Trump"].indexOf(d.last) != -1' | \
  ndjson-reduce '(p[d.statepostal] = p[d.statepostal] || []).push({name: d.last, votecount: d.votecount, votepct: d.votepct, bool_winner: d.winner}), p' '{}' | \
  ndjson-split 'Object.keys(d).map(key => ({statepostal: key, votes: d[key]}))' | \
  ndjson-map '{"statepostal": d.statepostal, "votes": d.votes.filter(obj => obj.name != "").sort((a, b) => b.bool_winner - a.bool_winner).sort((a, b) => b.votecount - a.votecount)}' | \
  ndjson-map '{"statepostal": d.statepostal, "leader": d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount ? d.votes[0].name : "even", "winner_or_leading": d.votes[0].bool_winner == true ? d.votes[0].name + "_winner"  : d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount && d.votes[0].bool_winner == false ? d.votes[0].name + "_leader" : "even", "winner_margin": (d.votes[0].votepct - d.votes[1].votepct).toFixed(2)}' | \
  ndjson-join --left 'd.statepostal' 'd.abbreviation' - <(cat json/state-electoral-votes-and-history.json | jq -c ".[]") | \
  ndjson-map 'Object.assign(d[0], d[1])' > spatial/prez_state_winners.tmp.ndjson

# oining winners to US topojson
ndjson-split 'd.objects.states.geometries' < spatial/states-albers-10m.json | \
  ndjson-map '{"type": d.type, "arcs": d.arcs, "properties": {"name": d.properties.name}}' | \
  ndjson-join --right 'd.properties.name' 'd.name' - spatial/prez_state_winners.tmp.ndjson | \
  ndjson-map '{"type": d[0].type, "arcs": d[0].arcs, "properties": {"name": d[0].properties.name, "leader": d[1].leader, "winner_or_leading": d[1].winner_or_leading, "winner_margin": d[1].winner_margin}}' | \
  ndjson-reduce 'p.geometries.push(d), p' '{"type": "GeometryCollection", "geometries":[]}' | \
  ndjson-join '1' '1' <(ndjson-cat spatial/states-albers-10m.json) - | \
  ndjson-map '{"type": d[0].type, "bbox": d[0].bbox, "transform": d[0].transform, "objects": {"states": {"type": "GeometryCollection", "geometries": d[1].geometries}}, "arcs": d[0].arcs}' > spatial/states-electoral-final-topo.json &&

# Converting to geojson and flipping
topo2geo states=- < spatial/states-electoral-final-topo.json | \
  geoproject 'd3.geoIdentity().reflectY(true)' > spatial/states-electoral-final-geo.json

# Colorizing SVG with leader/winner dilineated
mapshaper spatial/states-electoral-final-geo.json \
  -quiet \
  -colorizer name=calcFill colors='#115E9B,#CFCFCF,#AE191C,#CFCFCF,#CFCFCF,#E7E7E7' nodata='#EAEAEA' categories='Biden_winner,Biden_leader,Trump_winner,Trump_leader,no-votes,even' \
  -style fill='calcFill(winner_or_leading)' \
  -o id-field=name format=svg -
  # spatial/mn_2020_general_prez_electoral.svg

  #CFCFCF
  # -colorizer name=calcFill colors='#115E9B,#115E9B85,#AE191C,#AE191C85,#F0F0F0,#E7E7E7' nodata='#EAEAEA' categories='Biden_winner,Biden_leader,Trump_winner,Trump_leader,no-votes,even' \

# Colorizing SVG with only leader
# mapshaper spatial/states-electoral-final-geo.json \
#   -quiet \
#   -colorizer name=calcFill colors='#115E9B,#AE191C,#F0F0F0,#E7E7E7' nodata='#EAEAEA' categories='Biden,Trump,no-votes,even' \
#   -style fill='calcFill(leader)' \
#   -o id-field=name format=svg -
#   spatial/mn_2020_general_prez_electoral.svg
