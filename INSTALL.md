# icinga-sybase

## Quick Install Guide

1. Pull/clone the repository from GitHub

2. Install the stored procedure on your Database Server

```
isql -U<username> -S<DSQUERY> -P<password> -i sp_dba_nagios.sql
```
You may get an error here due to a missing table(see docs for details)

You can now test that the stored procedure is loaded and working

```
isql -U<username> -S<DSQUERY> -P<password> -w1000
1> sp_dba_nagios 3,10,20
2> go
SYB Blocked Processes : 0 - ok
(return status = 0)
```

3. Install the check_syb.ksh
This is where you need some Icinga expertise, as we installed it into a plugins directory, modified the permissions for SELinux, (ls -alZ and chcon). We had a nagios unix account set up running an NRPE process to execute the command.

Your mileage will vary here.

You can now test the script works on the unix commandline

```
# ./check_syb.ksh 3 10 20
# SYB Blocked Processes : 0 - ok
```

4. Configure Icinga to run the checks

This will be determined by your local set up.

