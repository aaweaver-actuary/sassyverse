/* MODULE DOC
File: src/logging.sas

1) Purpose in overall project
- General-purpose core utility module used by sassyverse contributors and downstream workflows.

2) High-level approach
- Defines reusable macro helpers and their tests, with small wrappers around common SAS patterns.

3) Code organization and why this scheme was chosen
- Public macros are grouped by theme, followed by focused unit tests and guarded autorun hooks.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Define utility macros and any private helper macros they require.
- Where needed, lazily import dependencies (for example assert/logging helpers).
- Expose a small public API with deterministic text/data-step output.
- Include test macros that exercise nominal and edge cases.
- Run tests only when __unit_tests is enabled to avoid production noise.

5) Acknowledged implementation deficits
- Macro-language utilities have limited static guarantees and rely on disciplined caller inputs.
- Some historical APIs prioritize backward compatibility over perfect consistency.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _logging_bootstrap
- _log_resolve_dir
- toggle_log_level
- set_log_level
- clean_logger
- console_log
- logger
- logtype
- info
- dbg
- test_logging
- run_logging_tests

7) Expected side effects from running/include
- Defines 12 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): log_dir, log_file.
- Executes top-level macro call(s) on include: _logging_bootstrap, run_logging_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
- Initializing this module sets default logging globals (for example log_level/log_dir/log_file) when unset.
*/
/* Bootstrap the logging module */
%macro _logging_bootstrap;
	%if not %sysmacexist(shell) %then %sbmod(shell);
	%if not %symexist(log_level) %then %global log_level;
	%if %length(%superq(log_level))=0 %then %let log_level=INFO;
	%global log_dir;
	%global log_file;
	%if %length(%superq(log_dir))=0 %then %let log_dir=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
	%if %length(%superq(log_file))=0 %then %let log_file=sas.log;
	%let type_len=5;
%mend _logging_bootstrap;

%_logging_bootstrap;

/* Resolve the directory for the log file.

Given input directory, output macro variable to write resolved directory to.
If input directory is missing or doesn't exist, falls back to WORK path.
*/
%macro _log_resolve_dir(dir=, out_dir=_log_dir);
	%local _dir_in _dir_out;
	%let _dir_in=%superq(dir);
	%if %length(%superq(_dir_in))=0 %then %let _dir_out=%superq(log_dir);
	%else %let _dir_out=%superq(_dir_in);

	%if %length(%superq(_dir_out))=0 %then %let _dir_out=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
	%if not %sysfunc(dexist(%superq(_dir_out))) %then %let _dir_out=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));
	%let &out_dir=%superq(_dir_out);
%mend _log_resolve_dir;

/* Toggle the log level between INFO and DEBUG */
%macro toggle_log_level;
	%if "%upcase(%superq(log_level))"="INFO" %then %let log_level=DEBUG;
	%else %if "%upcase(%superq(log_level))"="DEBUG" %then %let log_level=INFO;
	%else %let log_level=INFO;
%mend toggle_log_level;

/* Set the log level to a specific value. Accepts DEBUG, INFO, D, DBG, I. */
%macro set_log_level(level);
	%local testval;
	%let testval=%sysfunc(lowcase(%sysfunc(strip(%superq(level)))));
	%if %length(%superq(testval))=0 %then %let testval=info;

	%if "&testval." = "debug" %then %let log_level=DEBUG;
	%else %if "&testval." = "d" %then %let log_level=DEBUG;
	%else %if "&testval." = "dbg" %then %let log_level=DEBUG;


	%else %if "&testval." = "info" %then %let log_level=INFO;
	%else %if "&testval." = "i" %then %let log_level=INFO;

	%else %let log_level=INFO;
%mend set_log_level;

%macro clean_logger(
	filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir= /*Directory to save the log file. Default: WORK path*/
);
	%local filepath _dir;
	%_log_resolve_dir(dir=%superq(dir), out_dir=_dir);
	%let filepath=&_dir./&filename.;

 /* We get the filepath.  */
	data _null_;
		length _fp $32767;
		_fp = symget('filepath');
		rc = filename('_logclr', _fp);
		if rc = 0 then rc = fdelete('_logclr');
		rc = filename('_logclr');
	run;
%mend clean_logger;

/* Logs a message to the console */
%macro console_log(msg=);
	%put %superq(msg);
	sysecho %superq(msg);
%mend console_log;

/* Formats a log message similarly to the way something like the logger in python would. */
%macro logger(
	msg= /* Message to print to the log. */
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir= /*Directory to save the log file. Default: WORK path*/
);
	%local filepath _dir _msg;
	%let _msg=%superq(msg); /* Message to print to the log. */
	%_log_resolve_dir(dir=%superq(dir), out_dir=_dir); /* Resolve the directory for the log file. */
	%let filepath=&_dir./&filename.; /* Construct the full file path for the log file. */

	/* Write the log message to the file */
	data _null_;
		length _fp _line $32767;
		_fp = symget('filepath');
		_line = symget('_msg');
		file _log filevar=_fp mod lrecl=32767;
		put _line;
	run;
%mend logger;

/* Common functionality for all the further log items */
%macro logtype(
	msg /* Message to print to the log. */
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir= /*Directory to save the log file. Default: WORK path*/
	, type=INFO /* Log level to print with. Default: INFO. Used in formatting the message, but does not gate whether the message is printed or not. */
	, to_console=1 /* Whether to also print the message to the console. Default: 1 (true). If true, prints the message to the console in addition to the log file. */
);
	%local ts uptype updated_msg _pad;
	%let ts=%sysfunc(putn(%sysfunc(datetime()), e8601dt19.));
	%let uptype=%upcase(%sysfunc(strip(%superq(type))));
	%if %length(%superq(uptype))=0 %then %let uptype=INFO;
	%let _pad=%eval(6 - %length(&uptype.));
	%if &_pad < 0 %then %let _pad=0;
	%let uptype=%sysfunc(left(&uptype.%sysfunc(repeat(%str( ), &_pad))));
	%let updated_msg=[&ts.] &uptype. | %superq(msg);
	%logger(msg=%superq(updated_msg), filename=&filename., dir=&dir.);
	%if %sysfunc(indexw(1 Y YES TRUE T ON, %upcase(%superq(to_console)))) > 0 %then %do;
		%console_log(msg=%superq(updated_msg));
	%end;

%mend logtype;

/* Formats a log message similarly to the way something like the logger in python would. */
%macro info(
	msg /* Message to print to the log. */
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir= /*Directory to save the log file. Default: WORK path*/
	, to_console=1 /* Whether to also print the message to the console. Default: 1 (true). If true, prints the message to the console in addition to the log file. */
);
	%logtype(msg=%superq(msg), filename=&filename., dir=&dir., type=INFO, to_console=&to_console.);
%mend info;

/* Formats a log message similarly to the way something like the logger in python would. */
%macro dbg(
	msg /* Message to print to the log. */
	, filename=sas.log /* Filename to save the log as. Default: sas.log */
	, dir= /*Directory to save the log file. Default: WORK path*/
	, to_console=1 /* Whether to also print the message to the console. Default: 1 (true). If true, prints the message to the console in addition to the log file. */
);
	%if %upcase(%superq(log_level))=DEBUG %then %do;
		%logtype(msg=%superq(msg), filename=&filename., dir=&dir., type=DEBUG, to_console=&to_console.);
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
		%test_case(set_log_level and toggle_log_level aliases normalize values);
			%set_log_level(dbg);
			%assertEqual(&log_level., DEBUG);
			%toggle_log_level;
			%assertEqual(&log_level., INFO);
			%toggle_log_level;
			%assertEqual(&log_level., DEBUG);
			%set_log_level(i);
			%assertEqual(&log_level., INFO);
			%set_log_level();
			%assertEqual(&log_level., INFO);
			%set_log_level(unknown);
			%assertEqual(&log_level., INFO);
		%test_summary;

		%test_case(resolve dir falls back to work when path is missing);
			%_log_resolve_dir(dir=/path/that/does/not/exist, out_dir=_resolved_bad_dir);
			%assertEqual(%upcase(%superq(_resolved_bad_dir)), %upcase(%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /))));
		%test_summary;

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

		%test_case(log lines include ISO timestamp and severity);
			proc sql noprint;
				select count(*) into :_fmt_cnt trimmed
				from work._loglines
				where prxmatch('/^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T/', strip(line)) > 0
					and (index(line, 'INFO') > 0 or index(line, 'DEBUG') > 0);
			quit;
			%assertTrue(%eval(&_fmt_cnt > 0), log format includes timestamp and level);
		%test_summary;

		%test_case(dbg is gated when log level is INFO);
			%set_log_level(INFO);
			%dbg(msg=debug should not write, filename=&logfile., dir=&workdir.);

			data work._loglines2;
				infile "&workdir./&logfile." truncover;
				length line $32767;
				input line $char32767.;
			run;

			proc sql noprint;
				select count(*) into :_dbg_blocked_cnt trimmed
				from work._loglines2
				where index(line, 'debug should not write') > 0;
			quit;

			%assertEqual(&_dbg_blocked_cnt., 0);
			%set_log_level(DEBUG);
		%test_summary;
	%test_summary;

	%let log_level=&prev_level;

	proc datasets lib=work nolist; delete _loglines _loglines2; quit;
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
