#!/bin/sh

curl -s http://download-data.deutschebahn.com/static/datasets/haltestellen/D_Bahnhof_2016_01_alle.csv \
| perl scripts/acronyms.pl \
> lib/Travel/Status/DE/IRIS/Stations.pm
