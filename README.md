MySQLDumpX
==========

A collection of bash scripts simplifying partial backups of MySQL databases.

Introduction
------------
With web applications becoming more and more complex also the number of tables
in their database is increasing. Beside content and configuration, many of the
current web applications also store temporary or aggregated data into the
database. In order to save resources it may be desirable to exclude or separate
derived data. This can lead to dramatically reduced file sizes and faster
restores.

With mysqldumpx it is possible to include and exclude tables from dumps in a
very flexible way. Inclusion and exclusion rules can contain patterns with
wildcards and may be shared among multiple configurations. If you run multiple
instances of e.g. Drupal or Piwik you may reuse your rules among all your
databases.

Also part of the collection is a bash script, which can be run as CGI script
when cron is not available or limited to http requests at the hosting machine.

CONFIGURATION
-------------
Users of mysqldumpx should be familiar with the mysqldump utility shipped with
mysql. A commented configuration file with examples of all available options is
available in the examples. Additional there are working configurations for
Drupal and Piwik available which you may use as a starting point for your
versions.

OPTIONS
-------
-d Debug mode : Log *notice* message to stderr as well as syslog

-c Checkonly mode : Check only required commands
