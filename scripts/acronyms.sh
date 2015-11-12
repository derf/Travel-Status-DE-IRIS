#!/bin/sh

curl -s http://data.deutschebahn.com/datasets/betriebsstellen/DBNetz-Betriebsstellenverzeichnis-Stand2015-05.csv \
| perl scripts/acronyms.pl \
> lib/Travel/Status/DE/IRIS/Stations.pm
