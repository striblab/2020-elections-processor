#!/bin/bash
set -o allexport; source .env; set +o allexport

# Getting vote totals and joining to state names
cat json/results-mn-county-latest.json | \
  jq -c ".[]" | \
  ndjson-filter 'd.level === "county" && d.officename === "President" && ["Biden", "Trump"].indexOf(d.last) != -1' | \
  ndjson-reduce '(p[d.reportingunitname] = p[d.reportingunitname] || []).push({name: d.last, votecount: d.votecount, votepct: d.votepct, bool_winner: d.winner}), p' '{}' | \
  ndjson-split 'Object.keys(d).map(key => ({reportingunitname: key, votes: d[key]}))' | \
  ndjson-map '{"county": d.reportingunitname, "votes": d.votes.filter(obj => obj.name != "").sort((a, b) => b.votecount - a.votecount)}' | \
  ndjson-map '{"county": d.county, "leader": d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount ? d.votes[0].name : "even", "winner_or_leading": d.votes.every(o => o.votecount == 0) ? "no-votes" : d.votes[0].votecount != d.votes[1].votecount && d.votes[0].bool_winner == true ? d.votes[0].name + "_winner" : d.votes[0].votecount != d.votes[1].votecount && d.votes[0].bool_winner == false ? d.votes[0].name + "_leader" : "even", "winner_margin": (d.votes[0].votepct - d.votes[1].votepct).toFixed(2)}' > spatial/prez_mn_counties.tmp.ndjson

# Joining winners to US topojson
ndjson-cat spatial/mn.json | ndjson-split 'd.objects.counties.geometries' | \
  ndjson-map '{"type": d.type, "arcs": d.arcs, "properties": {"name": d.properties.NAME}}' | \
  ndjson-join --right 'd.properties.name.toLowerCase()' 'd.county.toLowerCase()' - spatial/prez_mn_counties.tmp.ndjson | \
  ndjson-map '{"type": d[0].type, "arcs": d[0].arcs, "properties": {"name": d[0].properties.name, "leader": d[1].leader, "winner_or_leading": d[1].winner_or_leading, "winner_margin": d[1].winner_margin}}' | \
  ndjson-reduce 'p.geometries.push(d), p' '{"type": "GeometryCollection", "geometries":[]}' | \
  ndjson-join '1' '1' <(ndjson-cat spatial/mn.json) - | \
  ndjson-map '{"type": d[0].type, "bbox": d[0].bbox, "transform": d[0].transform, "objects": {"counties": {"type": "GeometryCollection", "geometries": d[1].geometries}}, "arcs": d[0].arcs}' > spatial/prez-mn-counties-final-topo.json

# Converting to geojson and flipping
topo2geo counties=- < spatial/prez-mn-counties-final-topo.json | \
  geoproject 'd3.geoConicConformal().parallels([45 + 37 / 60, 47 + 3 / 60]).rotate([94 + 15 / 60, 0])' | \
  geoproject 'd3.geoIdentity().reflectY(true)' > spatial/prez-mn-counties-final-geo.json
  # geoproject 'd3.geoIdentity().reflectY(true)' > spatial/prez-mn-counties-final-geo.json

# Colorizing SVG with only leader
mapshaper spatial/prez-mn-counties-final-geo.json \
  -quiet \
  -colorizer name=calcFill colors='#115E9B,#AE191C,#F0F0F0,#E7E7E7' nodata='#EAEAEA' categories='Biden,Trump,no-votes,even' \
  -style fill='calcFill(leader)' \
  -o id-field=name format=svg -
