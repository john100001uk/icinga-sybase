/******************************
**
** File : sp_dba_nagios.sql
** Desc : Runs checks on a SAP/Sybase database server
**
******************************/
USE sybsystemprocs
GO

IF EXISTS (SELECT 1 FROM sysobjects WHERE name = "sp_dba_nagios" AND type = "P")
	BEGIN
		PRINT 'dropping "sp_dba_nagios"'
		DROP PROC sp_dba_nagios
	END
GO

PRINT 'creating "sp_dba_nagios"'
GO
CREATE PROC sp_dba_nagios @check int=null,@warn_at int=null,@critical_at int=null
AS
--
set nocount on
declare @ok_exit 		tinyint,
	@warn_exit 		tinyint,
	@critical_exit 		tinyint,
	@unknown_exit 		tinyint,
	@dbid                 	int,
	@dbspacepct            	int,
	@dbname                 varchar(50),
	@msg_string		varchar(255),
	@sql_string             varchar(255)

select @ok_exit=0,
	@warn_exit=1,
	@critical_exit=2,
	@unknown_exit=3


if (@check = null)
begin
	print ' check_syb.ksh <report id> <warn_at> <critical_at> [ <dbname> ]'
	print ''
	print ' sp_dba_nagios [ null | 1-12 ] , @warn_at , @critical_at'
	print ' '
        print ' Parameter      Check                                Nos of params'
        print ' ---------      -----                                -------------'
        print ' null           This help message                                3'
        print ' 1              ASE Uptime                                       3'
        print ' 2              User Connections                                 3'
        print ' 3              Blocking Connections                             3'
        print ' 4              Transaction Log Used Percent                     4'
        print ' 5              Database Used Percent                            4'
        print ' 6              Replication Check                                4'
        print ' 7              New Object Check                                 4'
        print ' 8              Long Running Txn                                 3'
        print ' 9              Appserver Connection Check                       3'
        print ' 10             Phantom Lock Detection                           3'
        print ' 11             Open Object Check                                3'
        print ' 12             Last Txn Log Time                                3'
	print ''
	print ' @warn_at       Warning Threshold'
	print ' @critical_at   Critical Threshold'
	print ''
	print ' 4th Parameter  Database Name, provided via check_syb.ksh script'
	print '                see - /usr/lib64/nagios/plugins/check_syb.ksh'
	print ''

	return @unknown_exit
end

--
-- Parameter Check
--
select @msg_string='SYB Syntax Error : '
if (@critical_at = null)
	begin
		select @msg_string=@msg_string + 'Critical parameter not set!'
		print '%1!',@msg_string
		return @unknown_exit
	end
if (@warn_at = null)
	begin
		select @msg_string=@msg_string + 'Warning parameter not set!'
		print '%1!',@msg_string
		return @unknown_exit
	end

--
-- Uptime check
--
if (@check = 1)
begin
	declare @mins_since_boot int
	select  @mins_since_boot = datediff(mi,@@boottime,getdate())
	--
	if (@mins_since_boot < @critical_at)
		begin
			print 'SYB Uptime : %1! mins - critical',@mins_since_boot
			return @critical_exit
		end
	if (@mins_since_boot < @warn_at)
		begin
			print 'SYB Uptime : %1! mins - warning',@mins_since_boot
			return @warn_exit
		end
	else
		begin
			print 'SYB Uptime : %1! mins - ok',@mins_since_boot
			return @ok_exit 
		end
	
end

--
-- User check
--
if (@check = 2)
begin

	declare @user_count int
	select @msg_string='SYB User Cnxns = '
	-- Total cnxns
	select @user_count=count(*) 
	from master..sysprocesses
	where hostname is not null
	and dbid not in ( db_id("master"),db_id("dbccdb"),db_id("sybsystemprocs"),db_id("sybsystemdb"),db_id("model"))
	--
	select @msg_string=@msg_string + convert(varchar(5),@user_count)

	--
	if (@user_count > @critical_at)
		begin
			print '%1! - critical | user_count = %2!',@msg_string,@user_count
			return @critical_exit
		end
	if (@user_count > @warn_at)
		begin
			print '%1! - warning | user_count = %2!',@msg_string,@user_count
			return @warn_exit
		end
	else
		begin
                        print '%1! - ok | user_count = %2!',@msg_string,@user_count
                        return @ok_exit
                end
end

--
-- Blocking txns
--
if (@check = 3)
begin

	declare @block_count int
	select @msg_string='SYB Blocking Transations = '
	select @block_count=count(*) from master..sysprocesses where blocked > 0

        if (@block_count > @critical_at)
                begin
                        print 'SYB Blocked Processes : %1! - critical | block_count = %2!',@block_count,@block_count
                        return @critical_at
                end
        if (@block_count > @warn_at)
                begin
                        print 'SYB Blocked Processes : %1! - warning | block_count = %2!',@block_count,@block_count
                        return @warn_exit
                end
        else
                begin
                        print 'SYB Blocked Processes : %1! - ok | block_count = %2!',@block_count,@block_count
                        return @ok_exit
                end


end

--
-- Transaction log used percent
--
if (@check = 4)
begin
        declare @ismixedlog           int ,
                @total_pages          numeric(19,1),
                @free_pages           numeric(19,1),
                @used_pages           numeric(19,1),
                @used_pages_wo_APs    numeric(19,1),
                @clr_pages            numeric(19,1),
                @pct_used       numeric(5,2)

        set @dbid = db_id()

        select @ismixedlog = (db.status2 & 32768)
        from master.dbo.sysdatabases db
        where db.dbid = @dbid

        select @clr_pages = lct_admin("reserved_for_rollbacks", @dbid)
        select @free_pages = lct_admin("logsegment_freepages", @dbid)
                             - @clr_pages

        select @total_pages = sum(u.size)
        from master.dbo.sysusages u
        where u.segmap & 4 = 4
        and u.dbid = @dbid

        if (@ismixedlog = 32768)
        begin
                /*
                ** For a mixed log and data database, we cannot
                ** deduce the log used space from the total space
                ** as it is mixed with data. So we take the expensive
                ** way of scanning syslogs, AP-by-AP and then extent-by-extent.
                */
                select @used_pages_wo_APs = lct_admin("num_logpages", @dbid)

                /* Account allocation pages as used pages */
                select @used_pages = @used_pages_wo_APs + (@total_pages / 256)
        end
        else
        begin
                /* Dedicated log database */
                select @used_pages = @total_pages - @free_pages - @clr_pages

                /* See note (1) above */
                set @used_pages_wo_APs =
                        (@total_pages - ( @total_pages / 256 ) - @free_pages)
        end

        select @pct_used=convert(numeric(5,2),(@used_pages/@total_pages) * 100)
        select @msg_string='SYB Log Used Percent in ' + db_name() + ' = ' + convert(varchar(6),@pct_used) + '%'
        -- Out put message
        if (@pct_used > @critical_at)
                begin
                        print '%1! - critical',@msg_string
                        return @critical_exit
                end
        if (@pct_used > @warn_at)
                begin
                        print '%1! - warning',@msg_string
                        return @warn_exit
                end
        else
                begin
                        print '%1! - ok',@msg_string
                        return @ok_exit
                end

end

--
-- Database Used Percent
-- 
if (@check = 5)
begin
	set @dbid = db_id()
	select @pct_used = ceiling(100 * (1 - 1.0 * sum(case when u.segmap != 4 
				then curunreservedpgs(u.dbid, u.lstart, u.unreservedpgs) end) / sum(case when u.segmap != 4 then u.size end)))
			from master..sysdatabases d, master..sysusages u
			where u.dbid = @dbid
			and d.dbid  = @dbid
			and d.status != 256
	select @msg_string='SYB Data Used Percent in ' + db_name() + ' = ' + convert(varchar(6),@pct_used) + '%'
	-- Out put message
        if (@pct_used > @critical_at)
                begin
                        print '%1! - critical | data_pct_used = %2!',@msg_string, @pct_used
                        return @critical_exit
                end
        if (@pct_used > @warn_at)
                begin
                        print '%1! - warning | data_pct_used = %2!',@msg_string, @pct_used
                        return @warn_exit
                end
        else
                begin
                        print '%1! - ok | data_pct_used = %2!',@msg_string, @pct_used
                        return @ok_exit
                end
--                        print 'SYB Blocked Processes : %1! - ok | block_count = %2!',@block_count,@block_count
end

--
-- Rep Agent + Latency Check
--
if (@check = 6)
begin
        declare @ra_yes                 tinyint,
                @trunc_marker           tinyint

        select @dbid = db_id()
        select @ra_yes = 0,@trunc_marker = 0

        if exists (select * from master..sysprocesses where dbid=@dbid and cmd like '%REP AGENT%')
                select @ra_yes = 1
        if exists (select * from master..syslogshold where dbid=@dbid and name like '%replication_truncation_point%')
                select @trunc_marker=1

        if (@ra_yes + @trunc_marker = 2) /* A working PDB Show db name and page scan count */
                begin
                        select @msg_string='SYB Rep Check : PDB = ' + db_name(@dbid) + ' ; Page = ' + convert(varchar(20),page) + ' - ok' from master..syslogshold where dbid=@dbid and name like '%replication_truncation_point%'
                        print @msg_string
                        return @ok_exit
                end

        if (@ra_yes + @trunc_marker = 1) /* Something not's right here - raise a critical with advisory */
                begin
                        select @msg_string='SYB Rep Check : RepAgent not running or missing LTM - critical'
                        print @msg_string
                        return @critical_exit
                end

        if (@ra_yes + @trunc_marker = 0) /* A working replicate - do a latency check */
                begin
                        declare @max_ident      numeric(20),
                                @latency_sec    int

                        select @sql_string='select @max_ident=max(ident) from ' + db_name(@dbid) + '..dba_repcheck_tab'
                        exec(@sql_string)

                        select @sql_string='select @latency_sec=datediff(ss,insert_time,replicate_time) from ' + db_name(@dbid) + '..dba_repcheck_tab where ident = @max_ident'
                        exec(@sql_string)


                        select @msg_string='SYB Rep Check : RDB = ' + db_name(@dbid) + ' ; Latency = ' + convert(varchar(20),@latency_sec) + ' secs'
                        if (@latency_sec > @critical_at)
                                begin
                                        select @msg_string=@msg_string + ' - critical'
                                        print @msg_string
                                        return @critical_exit
                                end
                        if (@latency_sec > @warn_at)
                                begin
                                        select @msg_string=@msg_string + ' - warning'
                                        print @msg_string
                                        return @warn_exit
                                end
                        else
                                begin
                                        select @msg_string=@msg_string + ' - ok'
                                        print @msg_string
                                        return @ok_exit
                                end
                end
end

--
-- New Object Check
--
if (@check = 7)
begin
        declare @newobjs        int
        select @sql_string='select @newobjs=count(*) from sysobjects where crdate > dateadd(mi,-@warn_at,getdate())'
	select @dbname=db_name()
        exec(@sql_string)
        select @msg_string='SYB New Object Count : ' + convert(varchar(5),@newobjs)
        if (@newobjs = 0)
                begin
                        select @msg_string='SYB New Object Count : ' + convert(varchar(5),@newobjs) + ' new objects in ' + @dbname + ' - ok'
                        print @msg_string
                        return @ok_exit
                end
        else
                begin
                        select @msg_string='SYB New Object Count : ' + convert(varchar(5),@newobjs) + ' new objects in ' + @dbname + ' - warning'
                        print @msg_string
                        return @warn_exit
                end
end

--
-- Long Running Txn
--
if (@check = 8)
begin
        declare @oldesttxntime  datetime
	-- don't include repmarker here (due to NY low volumes)
        select @oldesttxntime = min(starttime) from master..syslogshold
	where name not like '%replication_truncation_point%'
	--
        if ( @oldesttxntime = 'Jan  1 1900 12:00AM' ) -- set to null if this date, DUMP DATABASE
                select @oldesttxntime=null
	--
        select @msg_string='SYB Long Running Txn : '

        -- null, no txn detected
        if (@oldesttxntime = NULL)
        begin
                select @msg_string=@msg_string+'None Detected - ok'
                print '%1!',@msg_string
                return @ok_exit
        end

        -- less than warn_at threshold
        if (@oldesttxntime > dateadd(mi,-@warn_at,getdate()))
        begin
                select @msg_string=@msg_string+'None Detected - ok'
                print '%1!',@msg_string
                return @ok_exit
        end

        -- older that warn threshold
        if (@oldesttxntime < dateadd(mi,-@critical_at,getdate()))
        begin
                select @msg_string=@msg_string + 'Spid=' + convert(varchar(5),spid) +
                                                ' ; Db=' + db_name(dbid) +
                                                ' ; Started at ' + convert(varchar(20),starttime) +
                                                ' ; Txn=' + rtrim(name) + ' - critical'
                                        from master..syslogshold where starttime = @oldesttxntime
                print '%1!',@msg_string
                return @critical_exit
        end
        else
        begin
                select @msg_string=@msg_string + 'Spid=' + convert(varchar(5),spid) +
                                                ' ; Db=' + db_name(dbid) +
                                                ' ; Started at ' + convert(varchar(20),starttime) +
                                                ' ; Txn=' + rtrim(name) + ' - warning'
                                        from master..syslogshold where starttime = @oldesttxntime
                print '%1!',@msg_string
                return @warn_exit
        end
end


--
-- Appserver Connections Check
--
if (@check = 9)
begin
        declare @maxcons        int,
                @gotwarn        tinyint,
                @host           varchar(30)

        -- Populate table with top three busiest appservers
        select top 3 count(hostname) nos, hostname
        into #appsrvs
        from master..sysprocesses
        group by hostname
        order by count(hostname) desc

        -- max cons for loop
        select @maxcons=max(nos) from #appsrvs
        select @msg_string='SYB Appserver Connections : '

        -- loop for top three into msg_string
        while @maxcons > 0
        begin
                select @maxcons=max(nos) from #appsrvs

                if (@maxcons = null)
                begin
                        break
                end

                select @host = hostname from #appsrvs where nos=@maxcons

                select @msg_string=@msg_string + convert(varchar(6),@maxcons) + '/' + @host + ' ; '
                if (@maxcons > @warn_at)
                        select @gotwarn=1

                delete from #appsrvs where nos=@maxcons and hostname=@host
        end -- end while loop

        if (@gotwarn=1)
                begin
                        select @msg_string=@msg_string + ' - warning'
                        print '%1!',@msg_string
                        return @warn_exit
                end
        else
                begin
			select @msg_string=@msg_string + ' - ok'
                        print '%1!',@msg_string
                        return @ok_exit
                end
end

--
-- Phantom Lock Check
--
if (@check = 10)
begin
        declare @phantom_locks int
        select  @phantom_locks = count(*) from master..syslocks where spid not in (select spid from master..sysprocesses)
        --
        if (@phantom_locks >= @critical_at)
                begin
                        print 'SYB Phantom Lock : %1! Phantom Locks Detected - critical',@phantom_locks
                        return @critical_exit
                end
        else
                begin
                        print 'SYB Phantom Lock : %1! Phantom Locks Detected - ok',@phantom_locks
                        return @ok_exit
                end

end

--
-- Open Object Check
--
if (@check = 11)
begin
        declare @num_active	numeric(6,1),
		@max_open	numeric(6,1),
		@pc		numeric(6,1)
        select @max_open =	convert(numeric(6,0),value) from master..syscurconfigs where config=107
	select @num_active=	convert(numeric(6,0),config_admin(22,107,2,0,"open_object_reuse_requests",NULL))
	select @pc	=	convert(numeric(6,0),( @num_active / @max_open ) * 100.0)
        --
        if (@pc >= @critical_at)
                begin
                        print 'SYB Open Object Check : %1! percent Open Object Used - critical | pc = %2!',@pc,@pc
                        return @critical_exit
                end
	if (@pc > @warn_at)
		begin
			print 'SYB Open Object Check : %1! percent Open Object Used - warning | pc = %2!',@pc,@pc
			return @warn_exit
		end
        else
                begin
                        print 'SYB Open Object Check : %1! percent Open Object Used - ok | pc = %2!',@pc,@pc
                        return @ok_exit
                end
end

--
-- Last Txn Log Time
--  As an offline database is not accessible to execute a sp in as per other 4 parameter checks. 
--  This generates a warning only and @critical_at is used to pass a dbid in
--
begin
        declare @dumpdate	datetime,
		@now		datetime,
		@delta_hrs	int

        select	@now		= getdate(),
		@dbname		= db_name(@critical_at)
	
	select 	@dumpdate	= dumptrdate from master..sysdatabases where dbid = @critical_at -- A bit of a hack!
	select 	@delta_hrs	=  datediff(hh,@dumpdate,@now)
        --
        if (@delta_hrs >= @warn_at)
                begin
                        print 'SYB Last Txn Log Time : Db : %1! - Last txnlog load %2! hrs ago - warning',@dbname,@delta_hrs
                        return @critical_exit
                end
        else
                begin
                        print 'SYB Last Txn Log Time : Db : %1! - Last txnlog load %2! hrs ago - ok',@dbname,@delta_hrs
                        return @ok_exit
                end
end
 
GO
grant execute on sp_dba_nagios to mon_role
go


