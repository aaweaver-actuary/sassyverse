%macro _logging_bootstrap;
	%if not %sysmacexist(shell) %then %sbmod(shell);
%mend _logging_bootstrap;

%_logging_bootstrap;

%global log_level;
%let log_level=INFO;
%let type_len=5;

%macro toggle_log_level;
	%if "&log_level."="INFO" %then %let log_level=DEBUG;
	%else %if "&log_level."="DEBUG" %then %let log_level=INFO;
	%else %let log_level=INFO;
%mend toggle_log_level;

%macro set_log_level(level);
	%let testval=%sysfunc(lowcase(&level.));

	%if "&testval." = "debug" %then %let log_level=DEBUG;
	%else %if "&testval." = "d" %then %let log_level=DEBUG;
	%else %if "&testval." = "dbg" %then %let log_level=DEBUG;
		

	%else %if "&testval." = "info" %then %let log_level=INFO;
	%else %if "&testval." = "i" %then %let log_level=INFO;
	
	%else %let log_level=INFO;
%mend set_log_level;

%macro clean_logger(
	filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir=/sas/data/project/EG/ActShared/SmallBusiness/aw/logfiles /*Directory to save the log file. Default: EGSB/aw/logfiles*/
);
	%let filepath=&dir./&filename.;

	%shell(rm &filepath.);
	%shell(mkdir -p &dir.); 
%mend clean_logger;

%macro console_log(msg);
	%put &msg.;
	sysecho &msg.;
%mend console_log;

%macro logger(
	msg= /* Message to print to the log. */
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir=/sas/data/project/EG/ActShared/SmallBusiness/aw/logfiles /*Directory to save the log file. Default: EGSB/aw/logfiles*/
);
	%let filepath=&dir./&filename.;

	%shell(mkdir -p &dir.); 

	data _null_;
		file "&filepath." mod;
		put "&msg.";
	run;
%mend logger;

/* Common functionality for all the further log items */
%macro logtype(
	msg /* Message to print to the log. */ 
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir=/sas/data/project/EG/ActShared/SmallBusiness/aw/logfiles /*Directory to save the log file. Default: EGSB/aw/logfiles*/
	, type=INFO
);
	%let today = %sysfunc(today());
	%let y=%sysfunc(year(&today.), z4.);
	%let m=%sysfunc(month(&today.), z2.);
	%let d=%sysfunc(day(&today.), z2.);

	%let h=%sysfunc(hour(&today.), z2.);
	%let mi=%sysfunc(minute(&today.), z2.);
	%let s=%sysfunc(second(&today.), z2.);

	%let ts=&y.-&m.-&d. &h.:&mi.:&s.;

	%let uptype=%sysfunc(upcase(&type.));
    %let uptype=%sysfunc(left(&uptype.%sysfunc(repeat(%str( ), %eval(6 - %length(&uptype.))))));

	%let updated_msg=[&ts.] &uptype. | %unquote(%sysfunc(tranwrd(%nrbquote(&msg.), '"', '')));
	%logger(msg=&updated_msg., filename=&filename., dir=&dir.);

%mend logtype;

/* Formats a log message similarly to the way something like the logger in python would. */
%macro info(
	msg /* Message to print to the log. */ 
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir=/sas/data/project/EG/ActShared/SmallBusiness/aw/logfiles /*Directory to save the log file. Default: EGSB/aw/logfiles*/
);
	%logtype(msg=&msg., filename=&filename., dir=&dir., type= INFO);
%mend info;

/* Formats a log message similarly to the way something like the logger in python would. */
%macro dbg(
	msg /* Message to print to the log. */ 
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir=/sas/data/project/EG/ActShared/SmallBusiness/aw/logfiles /*Directory to save the log file. Default: EGSB/aw/logfiles*/
);
	%if &log_level.=DEBUG %then %do;
		%logtype(msg=&msg., filename=&filename., dir=&dir., type=DEBUG);
	%end;
%mend dbg;

%macro test_logging;
	%if not %sysmacexist(assertTrue) %then %sbmod(assert);

	%local workdir logfile prev_level;
	%let workdir=%sysfunc(pathname(work));
	%let logfile=log_test.log;
	%let prev_level=&log_level;

	%set_log_level(DEBUG);

	%test_suite(Testing logging.sas);
		%test_case(info and dbg write lines);
			%info(msg=hello info, filename=&logfile., dir=&workdir.);
			%dbg(msg=hello debug, filename=&logfile., dir=&workdir.);

			data work._loglines;
				infile "&workdir./&logfile." truncover;
				length line $32767;
				input line $char32767.;
			run;

			proc sql noprint;
				select count(*) into :_info_cnt trimmed
				from work._loglines
				where index(line, 'INFO') > 0 and index(line, 'hello info') > 0;
				select count(*) into :_dbg_cnt trimmed
				from work._loglines
				where index(line, 'DEBUG') > 0 and index(line, 'hello debug') > 0;
			quit;

			%assertTrue(%eval(&_info_cnt > 0), info wrote to log file);
			%assertTrue(%eval(&_dbg_cnt > 0), dbg wrote to log file);
		%test_summary;
	%test_summary;

	%let log_level=&prev_level;

	proc datasets lib=work nolist; delete _loglines; quit;
%mend test_logging;

/* Macro to run logging tests when __unit_tests is set */
%macro run_logging_tests;
	%if %symexist(__unit_tests) %then %do;
		%if %superq(__unit_tests)=1 %then %do;
			%test_logging;
		%end;
	%end;
%mend run_logging_tests;

%run_logging_tests;