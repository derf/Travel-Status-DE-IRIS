#!/bin/sh

curl -s http://fahrweg.dbnetze.com/file/fahrweg-de/2394144/vHBDX5OndmGwv-JTA9EzuNArX1E/2361656/data/betriebsstellen.pdf \
| pdftotext -layout - - | perl scripts/acronyms.pl \
> lib/Travel/Status/DE/IRIS/Stations.pm
