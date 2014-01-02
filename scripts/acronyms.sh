#!/bin/sh

curl -s http://www.db-netz.de/file/2361656/data/betriebsstellen.pdf \
| pdftotext -raw - - | perl scripts/acronyms.pl \
> lib/Travel/Status/DE/IRIS/Stations.pm
