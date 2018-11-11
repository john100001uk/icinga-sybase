#!/bin/ksh
#-------------------------------------------------------------------------------
## File : check_syb.ksh 
## Desc : Run by Icinga/NRPE Agent, calls sp_dba_nagios and handles return statuses
#-------------------------------------------------------------------------------
# Usage
#
# check_syb.ksh <report id> <warn_at> <critical_at> [ <dbname> ]
#
# Parameter      Check                                Nos of params
# ---------      -----                                -------------
# null           This help message                                3
# 1              ASE Uptime                                       3
# 2              User Connections                                 3
# 3              Blocking Connections                             3
# 4              Transaction Log Used Percent                     4
# 5              Database Used Percent(via shell script only)     4
# 6              Replication Check                                4
# 7              New Object Check                                 4
# 8              Long Running Txn                                 3
# 9              Appserver Connection Check                       3
# 10             Phantom Lock Detection                           3
# 11             Open Object Check                                3
# 12             Last Txn Log Time                                3
#
# warn_at        Warning Threshold
# critical_at    Critical Threshold
#
# dbame          Optional - for a db specific check, eg space used percent
#
#-------------------------------------------------------------------------------
#set -xv ## uncomment for debug
set -a
scriptname=${0##*/}

#-------------------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------------------
typeset -u upperhostname;upperhostname=`hostname`       #- Set up your
export DSQUERY=${upperhostname}_AS                      #- DSQUERY here
# Where this file is located
export NAGIOSSCRIPTDIR=/usr/lib64/nagios/plugins
# Sybase version dependancies, this will find the latest version
if [ -d /opt/sybase/ASE1602 ] ; then
        export SYBASE=/opt/sybase/ASE1602
fi
if [ -d /opt/sybase/ASE1570 ] ; then
        export SYBASE=/opt/sybase/ASE1570
fi
#
. ${SYBASE}/SYBASE.sh
export PATH=$PATH:$NAGIOSSCRIPTDIR
# The NAGIOS_USER must be a valid login on ASE
export NAGIOS_USER=nagios
NAGIOS_PASSWD=XXXXXXXXXXXX                             #- There are more secure ways
#                                                      #- of passing the password!
#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

# runs some SQL into the local sybase server
runsql () {
isql -U $NAGIOS_USER -S $DSQUERY -w2000 -D $NAGIOS_DATABASE <<eof
$NAGIOS_PASSWD
`printf "$1 \ngo\n"`
eof
}

# Processes the results of runsql collecting the SQL 'return status' and exiting this shell with it.
# If login to the server fails and/or a CT-LIB error is encountered exit status 3 is returned.
return_status() {
awk '   $1 ~ /SYB/  { msg=$0 }
        $1 ~ /\(return/  {  exit_status=substr($0,18,1)}
        $0 ~ /CT-LIBRARY error/  {  msg=("SYB " $0 " detected - critical") ; exit_status=255 }
        END {
                print msg
                if ( exit_status >= 0 && exit_status <= 2 )
                        exit exit_status
                else
                        exit 3
        }'
}
#-------------------------------------------------------------------------------
# Program starts here
#-------------------------------------------------------------------------------
# Sort out the dbname for runsql function
if [ "$#" -eq 3 ] ; then
	NAGIOS_DATABASE=master
elif [ "$#" -eq 4 ] ; then
	NAGIOS_DATABASE=$4
fi

# Run the query
# If $1 = 5 - a database space report is required, it's easier and more future proof to
# use the SAP sp_spaceused stored procedure and process the results at the shell level.
case $1 in
	5) ## Got to go with sp_spaceused for free space percent
		rm -f /tmp/syb_space_nagios_${NAGIOS_DATABASE}
		runsql "sp_spaceused" > /tmp/syb_space_nagios_${NAGIOS_DATABASE}
		echo "ThrEsh $2 $3" >> /tmp/syb_space_nagios_${NAGIOS_DATABASE}
		TotKB=$(cat /tmp/syb_space_nagios_${NAGIOS_DATABASE} | grep ${NAGIOS_DATABASE} | awk '{print $2 * 1024}')
		UsedKB=$(cat /tmp/syb_space_nagios_${NAGIOS_DATABASE} | grep KB | awk '{print $1}')
		Wat=$(grep ThrEsh /tmp/syb_space_nagios_${NAGIOS_DATABASE} | awk '{print $2}')
		Cat=$(grep ThrEsh /tmp/syb_space_nagios_${NAGIOS_DATABASE} | awk '{print $3}')
		echo "$NAGIOS_DATABASE $TotKB $UsedKB $Wat $Cat" | awk 'NR == 1 {
			pc=($3/$2)*100

			if (pc > $5)
				{
					printf("SYB Used Space in %s = %d percent - critical\n",$1,pc);
					exit 2
				}
			if (pc > $4)
				{
					printf("SYB Used Space in %s = %d percent - warning\n",$1,pc)
					exit 1
				}
			else
				{
				printf("SYB Used Space in %s = %d percent - ok\n",$1,pc)
				exit 0
				}
			}'
	;;
	*) ## All other reports come through here
	if [ "$#" -lt 3 ] || [ "$#" -gt 4 ] ; then
		## This is the usage statement
		printf "\n ${scriptname} - SYB Monitoring for Sybase\n\n"
		runsql "sp_dba_nagios" |grep -v Password
	else
		## Run the stored procedure, for $4, the dbname see runsql function
			runsql "sp_dba_nagios $1,$2,$3" | return_status
	fi
	;;
esac
