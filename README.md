Travel::Status::DE::IRIS - Interface to IRIS based web departure monitors
---

<https://finalrewind.org/projects/Travel-Status-DE-IRIS/>


Dependencies
---

* perl version 5.14.2 or newer
* Class::Accessor
* DateTime
* DateTime::Format::Strptime
* Geo::Distance
* List::Compare
* List::MoreUtils
* List::UtilsBy
* LWP::UserAgent
* Text::LevenshteinXS
* XML::LibXML

Additional dependencies for building this module:

* File::Slurp
* JSON

Note about Text::LevenshteinXS: This module is old and unmaintained, but
appears to be packaged for slightly more distros than its successor
Text::Levenshtein::XS. If it is not available for your distro (and you do
not wish to build it), the following drop-in replacements are available:

* Text::Levenshtein::XS
* Text::Levenshtein (about 10 times slower than the XS modules)

To use them, run:

```
sed -i 's/Text::LevenshteinXS/Text::Levenshtein::XS/g' Build.PL lib/Travel/Status/DE/IRIS/Stations.pm
```

or

```
sed -i 's/Text::LevenshteinXS/Text::Levenshtein/g' Build.PL lib/Travel/Status/DE/IRIS/Stations.pm
```

Installation
---

From a release tarball:

```
perl Build.PL
./Build
sudo ./Build install
```

From git:

```
perl Build.PL
./Build
./Build manifest
sudo ./Build install
```

See also the Module::Build documentation.

You can then run `man Travel::Status::DE::IRIS`.
This distribution also ships the script 'db-iris', see `man db-iris`.

Managing stations
---

Travel::Status::DE::IRIS needs a list of train stations to operate, which is
located in `share/stations.json`. There are two recommended editing methods.

Automatic method, e.g. to incorporate changes from Open Data sources:

* modify stations.json with a script in any JSON-aware language you like
* run `./json2json` in the share diretcory. This performs consistency checks and
  transforms stations.json into its canonical format, which simplifies tracking
  of changes and reduces diff size

Manual method:

* run `./json2csv` in the share directory
* modify stations.csv automatically or manually (e.g. with LibreOffice Calc)
* run `./csv2json` in the share directory

If the changes you made are suitable for inclusion in Travel::Status::DE::IRIS,
please [open a pull request](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork) afterwards.

Please only include stations which are usable with DB IRIS, that is, which have
both DS100 and EVA numbers. If

```
curl -s https://iris.noncd.db.de/iris-tts/timetable/station/EVANUMBER
```

and

```
curl -s https://iris.noncd.db.de/iris-tts/timetable/station/DS100
```

return a `<station>` element with "name", "eva" and "ds100" attributes, you're
good to go.

Note that although EVA numbers are often identical with UIC station IDs,
there are stations where this is not the case.
