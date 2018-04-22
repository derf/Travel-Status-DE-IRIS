#!/bin/sh

curl -s http://download-data.deutschebahn.com/static/datasets/haltestellen/D_Bahnhof_2017_09.csv \
| perl scripts/acronyms.pl \
> lib/Travel/Status/DE/IRIS/Stations.pm
