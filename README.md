# icinga-sybase

# An Icinga Plugin to Monitor SAP/Sybase Database Servers

## About
This consists of the following
1. sp_dba_nagios.sql - a database stored procedure that runs a series of checks on a SAP/Sybase database server
2. check_syb.ksh - a Korn shell script that can be run by an Icinga NRPE agent to return exit codes and messages for the Icinga Web Console

These scripts have performed monitoring of ASE versions 15.7/16.0 running on RHEL6 virtual servers with SELinux enabled.

## Licensing
GNU GENERAL PUBLIC LICENSE Version 3. Please feel free to modify these scripts. No liability can be accepted nor warranty given. See LICENSE for details

## Installation
See INSTALLATION.md for brief instructions or the docs directory for more detailed information. Icinga seems to be very configurable so it's quite difficult to provide exact instructions.

## Documentation
See docs directory for asciidoctor files

## ToDo
- [ ] check_syb.ksh should be more generic/configurable



