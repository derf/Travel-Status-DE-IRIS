Travel::Status::DE::IRIS - Interface to IRIS based web departure monitors
---

<https://finalrewind.org/projects/Travel-Status-DE-IRIS/>

Travel::Status::DE::IRIS and the accompanying **db-iris** program provide both
human- and machine-readable access to departure data at german train stations.
They can be used by Perl scripts or modules, on the command-line, and (via JSON
output) by other programs.

Local Installation
---

This will install db-iris and Travel::Status::DE::IRIS to a local directory.
They will not be made available system-wide; db-iris will not be added to
your program PATH. See the next section for system-wide installation.

All you need for this variant is **perl** (v5.14.2 or newer), **carton**
(packaged for many operating systems), and **libxml2** with development headers
(packaged as `libxml2-dev` on Debian-based Linux distributions).

After installing these, run the following command to install the remaining
dependencies:

```
carton install
```

You are now ready to use db-iris by providing Perl with the module paths
set up by carton and Travel::Status::DE::IRIS:

```
perl -Ilocal/lib/perl5 -Ilib bin/db-iris --version
```

For documentation, see `perldoc -F lib/Travel/Status/DE/IRIS.pm` and
`perldoc -F bin/db-iris`.

System-Wide Installation
---

This will install db-iris and Travel::Status::DE::IRIS in system-wide
directories in `/usr/local`, allowing them to be used on the command line and
by Perl scripts without the need to specify search paths or module directories.
Building and installation is managed by the **Module::Build** perl module.

For this variant, you must install Module::Build and all dependencies (see the
Dependencies section below) yourself. Many of them are packaged for Debian and
other Linux distributions. Run `perl Build.PL` to check dependency availability
-- if it complains about "ERRORS/WARNINGS FOUND IN PREREQUISITES", install the
modules it mentions and run `perl Build.PL` again. Repeat this process until it
no longer complains about missing prerequisites.

You are now ready to build and install the module.

If you downloaded a release tarball, use the following commands:

```
perl Build.PL
./Build
sudo ./Build install
```

If you are working with the git version, use these instead:

```
perl Build.PL
./Build
./Build manifest
sudo ./Build install
```

You can now use Travel::Status::DE::IRIS and db-iris like any other perl
module. See `man Travel::Status::DE::IRIS` and `man db-iris` for documentation.

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
