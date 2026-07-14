/* MODULE DOC
File: src/assert.sas

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
- _log_styles
- symbol_dne
- test_symbol_dne
- itit_globals
- reset_test_counts
- assertTrue
- assertFalse
- assertEqual
- assertNotEqual
- test_suite
- test_case
- test_summary
- test_assertions
- run_assertion_tests

7) Expected side effects from running/include
- Defines 14 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): logPASS, logFAIL, logERROR, testCount, testFailures, testErrors, testSuite, isCurrentlyInTestCase, currentTestCaseName, testCaseCount, testCaseFailures, testCaseErrors.
- Executes top-level macro call(s) on include: _log_styles, run_assertion_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro _bootstrap_assert;
	
%if %sysfunc(libref(sbfuncs)) ne 0 %then %do;
  libname sbfuncs "%sysfunc(pathname(work))";
%end;
%mend _bootstrap_assert;

%_bootstrap_assert;

%put======================>> Loading assert.sas;

%macro _log_styles;
	%global logPASS logFAIL logERROR;
	%let logPASS=NOTE: [PASS];
	%let logFAIL=ERROR: [FAIL];
	%let logERROR=ERROR: [ERROR];
%mend;

%_log_styles;

%macro symbol_dne(symbol);
	%if %symexist(%unquote(%str(&symbol.)))=0 %then %let out=1;
	%else %if "%sysfunc(strip(%unquote(%str(&symbol.))))"="" %then %let out=1;
	%else %let out=0;
	&out.
%mend;

%macro test_symbol_dne;
	%test_suite(Symbol DNE tests);

	%test_summary;
%mend test_symbol_dne;

%macro itit_globals;
	%if %symbol_dne(testCount) %then %do;
		%global testCount;
		%let testCount=0;
	%end;
	%if %symbol_dne(testFailures) %then %do;
		%global testFailures;
		%let testFailures=0;
	%end;
	%if %symbol_dne(testErrors) %then %do;
		%global testErrors;
		%let testErrors=0;
	%end;
%mend;

%macro reset_test_counts;
	%global testCount testErrors testFailures;
	%let testCount=0;
	%let testFailures=0;
	%let testErrors=0;
%mend;

%macro assertTrue(condition, message);
	/*
	Assert that the given condition that evaluates to either 0
	(for false) or 1 (for true) is true.

	Logs a PASS if 1, FAIL if 0, and ERROR if anything else.

	@param condition : Macro expression resolving to 1 for true
	or 0 for false
	@param message : A message that prints regardless of whether the
	test passes to identify and describe the test.
	 */
	%itit_globals;
	%if %symbol_dne(isCurrentlyInTestCase) %then %let isCurrentlyInTestCase=0;
	%let result=0;

	%let testPass=%eval(&testCount - &testFailures);
	%let testCount=%eval(&testCount + 1);

	%if %eval(&condition)=1 %then %do;
		%let result=1;
		%let testPass=%eval(&testPass + 1);
		%put &logPASS. - &testPass.|&testFailures.|&testErrors. - &message;
	%end;
	%else %if %eval(&condition)=0 %then %do;
		%let testFailures=%eval(&testFailures + 1);
		%put &logFAIL. - &testPass.|&testFailures.|&testErrors. - &message;
	%end;
	%else %do;
		%let result=-1;
		%let testErrors=%eval(&testErrors + 1);
		%put &logERROR. - &testPass.|&testFailures.|&testErrors. - &message.;
		%put &logERROR. - &testPass.|&testFailures.|&testErrors. - &condition.
			evaluates to %eval(&condition);
		%put &logERROR. - &testPass.|&testFailures.|&testErrors. - &condition.
			must evaluate to either 0 or 1;
	%end;

	%if &isCurrentlyInTestCase.=1 %then %do;
		%let testCaseCount=%eval(&testCaseCount + 1);
		%if %eval(&result=0) %then %let testCaseFailures=%eval(&testCaseFailures + 1);
		%else %if %eval(&result=-1) %then %let testCaseErrors=%eval(&testCaseErrors + 1);
	%end;

%mend;

%macro assertFalse(condition, message);
	%if %eval(&condition)=0 %then %let cond=1;
	%else %let cond=0;
	%assertTrue(%eval(&cond.), &message.);
%mend;

%macro assertEqual(actual, expected);
	%local _is_num_a _is_num_b _eq;
	%if %length(%superq(actual))=0 or %length(%superq(expected))=0 %then %do;
		%if %superq(actual)=%superq(expected) %then %let _eq=1;
		%else %let _eq=0;
	%end;
	%else %do;
	%let _is_num_a=%sysfunc(verify(%superq(actual),%str(0123456789.+-eE)));
	%let _is_num_b=%sysfunc(verify(%superq(expected),%str(0123456789.+-eE)));
	%if &_is_num_a=0 and &_is_num_b=0 %then %do;
		%let _eq=%sysevalf(%superq(actual) = %superq(expected));
	%end;
	%else %do;
		%if %superq(actual)=%superq(expected) %then %let _eq=1;
		%else %let _eq=0;
	%end;
	%end;
	%let message=Asserted that [%superq(actual)]=[%superq(expected)];
	%assertTrue(%eval(&_eq), %superq(message));
%mend;

%macro assertNotEqual(actual, expected);
	%local _is_num_a _is_num_b _eq;
	%if %length(%superq(actual))=0 or %length(%superq(expected))=0 %then %do;
		%if %superq(actual)=%superq(expected) %then %let _eq=1;
		%else %let _eq=0;
	%end;
	%else %do;
	%let _is_num_a=%sysfunc(verify(%superq(actual),%str(0123456789.+-eE)));
	%let _is_num_b=%sysfunc(verify(%superq(expected),%str(0123456789.+-eE)));
	%if &_is_num_a=0 and &_is_num_b=0 %then %do;
		%let _eq=%sysevalf(%superq(actual) = %superq(expected));
	%end;
	%else %do;
		%if %superq(actual)=%superq(expected) %then %let _eq=1;
		%else %let _eq=0;
	%end;
	%end;
	%let message=Asserted that [%superq(actual)]!=[%superq(expected)];
	%assertFalse(%eval(&_eq), %superq(message));
%mend;

/* options nonotes nosource nodetails; /* Suppress warnings that these functions were previously compiled */ */

/* proc fcmp outlib=sbfuncs.fn.assert; */
/* 	/* These subroutines are otherwise identical to the macros, but */
/* 	   are compiled	subroutines that can test data in a data step.*/ */
/* 	subroutine assertTrue(condition $, message $); */
/* 	length cmd $ 32767; */
/* 		cmd=strip(cats('%nrstr(%assertTrue)(', condition, ', "', message, '")')); */
/* 	put cmd=; */
/* 	call execute(cmd); */
/* 	endsub; */

/* 	subroutine assertFalse(condition $, message $); */
/* 	length cmd $ 32767; */
/* 	cmd=cats('%nrstr(%assertFalse)(', condition, ', "', message, '")'); */
/* 	put cmd=; */
/* 	call execute(cmd); */
/* 	/* call execute(cats('%nrstr(%assertFalse)(', condition, ', "', message, */
/* 	'")')); */ */
/* 	endsub; */

/* 	subroutine assertEqual(actual $, expected $); */
/* 	length cmd $ 32767; */
/* 	cmd=cats('%nrstr(%assertEqual)(', actual, ', ', expected, ')'); */
/* 	put cmd=; */
/* 	call execute(cmd); */
/* 	/* call execute(cats('%nrstr(%assertEqual)(', actual, ', ', expected')')); */ */
/* 	endsub; */

/* 	subroutine assertNotEqual(actual $, expected $); */
/* 	length cmd $ 32767; */
/* 	cmd=cats('%nrstr(%assertNotEqual)(', actual, ', ', expected, ')'); */
/* 	put cmd=; */
/* 	call execute(cmd); */
/* 	/* call execute(cats('%nrstr(%assertNotEqual)(', actual, ', ', expected')')); */ */
/* 	endsub; */
/* run; */

/* options notes source details; */
/* options cmplib=sbfuncs.fn; */;

%macro test_suite(name);
	%global testSuite isCurrentlyInTestCase;
	%let isCurrentlyInTestCase=0;
	%let testSuite=&name.;
	%put======================>> Running unit tests for &name.;
	%reset_test_counts;
%mend test_suite;


%macro test_case / parmbuff;
	%global currentTestCaseName isCurrentlyInTestCase testCaseCount testCaseFailures testCaseErrors;
	%global testCaseSysccStart testCaseSyserrStart;
	%local _buf _title _len;
	%let _buf=%superq(syspbuff);
	%let _len=%length(%superq(_buf));
	%if &_len >= 2 %then %do;
		%if %qsubstr(%superq(_buf), 1, 1)=%str(%() and %qsubstr(%superq(_buf), &_len, 1)=%str(%)) %then %do;
			%let _title=%qsubstr(%superq(_buf), 2, %eval(&_len-2));
		%end;
		%else %let _title=%superq(_buf);
	%end;
	%else %let _title=%superq(_buf);
	%let currentTestCaseName=%unquote(%superq(_title));
	%put======================>> Running test case: [&currentTestCaseName.];
	%let isCurrentlyInTestCase=1;
	%let testCaseCount=0;
	%let testCaseFailures=0;
	%let testCaseErrors=0;
	%let testCaseSysccStart=%sysfunc(inputn(%superq(syscc), best32.));
	%let testCaseSyserrStart=%sysfunc(inputn(%superq(syserr), best32.));
%mend test_case;

%macro test_summary;
	%if &isCurrentlyInTestCase.=1 %then %do;
		%local _tc_syscc_start _tc_syserr_start _tc_syscc_end _tc_syserr_end;
		%let _tc_syscc_start=%sysfunc(inputn(%superq(testCaseSysccStart), best32.));
		%let _tc_syserr_start=%sysfunc(inputn(%superq(testCaseSyserrStart), best32.));
		%let _tc_syscc_end=%sysfunc(inputn(%superq(syscc), best32.));
		%let _tc_syserr_end=%sysfunc(inputn(%superq(syserr), best32.));

		%if %sysevalf(&_tc_syscc_end > &_tc_syscc_start) or %sysevalf(&_tc_syserr_end > &_tc_syserr_start) %then %do;
			%let testErrors=%eval(&testErrors + 1);
			%let testCaseErrors=%eval(&testCaseErrors + 1);
			%put &logERROR. - Runtime/system error detected during test case [&currentTestCaseName.]. SYSCC &_tc_syscc_start -> &_tc_syscc_end, SYSERR &_tc_syserr_start -> &_tc_syserr_end.;
		%end;

		%put======================>> Test Case Summary;
		%put ;
		%put |----------------------------------|;
		%put | &currentTestCaseName;
		%put |----------------------------------|;
		%put |----------------------------------|;
		%put | Test Count: | &testCaseCount;
		%put |----------------------------------|;
		%put | Test Failures: | &testCaseFailures;
		%put |----------------------------------|;
		%put | Test Errors: | &testCaseErrors;
		%put |----------------------------------|;
		%put |----------------------------------|;
		%put ;

		%if &testCaseFailures=0 and &testCaseErrors=0 %then %put &logPASS. - All tests for [&currentTestCaseName.] passed;
		%else %put &logFAIL. - Some tests for [&currentTestCaseName.] failed;

		%put======================>> Test Case Summary [DONE];

		%let isCurrentlyInTestCase=0;
	%end;
	%else %do;
		%put======================>> Test Summary;
		%put ;
		%put |----------------------------------|;
		%put | &testSuite;
		%put |----------------------------------|;
		%put |----------------------------------|;
		%put | Test Count: | &testCount;
		%put |----------------------------------|;
		%put | Test Failures: | &testFailures;
		%put |----------------------------------|;
		%put | Test Errors: | &testErrors;
		%put |----------------------------------|;
		%put |----------------------------------|;
		%put ;
		%if &testFailures=0 and &testErrors=0 %then %put &logPASS. - All tests
			passed;
		%else %put &logFAIL. - Some tests failed;

		%put======================>> Test Summary [DONE];

	%end;
	%put======================>> Running unit tests for &testSuite [DONE];
%mend test_summary;

%put======================>> Loading assert.sas [DONE];

/* Test these assertion macros */
%macro test_assertions;
	%test_suite(Testing assert);

		%test_case(Testing macro versions of assertions);
			%assertTrue(1, 1 is true);
			%assertFalse(0, 0 is false);
			%assertEqual(1, 1);
			%assertNotEqual(1, 0);
			%assertEqual(%str(note='a,b'), %str(note='a,b'));
			%assertNotEqual(%str(note='a,b'), %str(note='a,c'));

			%assertTrue(%symbol_dne(asdafasdf), 'asdafasdf' was not previously defined);
		%test_summary;
	%test_summary;
%mend test_assertions;

/* Alias for test_assertions so I don't have to remember the full name */
%macro test_assert;
	%test_assertions;
%mend test_assert;

/* Macro to run assertion tests when __unit_tests is set */
%macro run_assertion_tests;
	%if %symexist(__unit_tests) %then %do;
		%if %superq(__unit_tests)=1 %then %do;
			%test_assertions;
		%end;
	%end;
%mend run_assertion_tests;

%run_assertion_tests;
/* MODULE DOC
File: src/lists.sas

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
- foreach
- transform
- len
- nth
- first
- last
- unique
- sorted
- push
- pop
- concat
- list_err
- test_lists
- run_lists_tests

7) Expected side effects from running/include
- Defines 14 macro(s) in the session macro catalog.
- May create/update GLOBAL macro variable(s): has_err.
- Executes top-level macro call(s) on include: run_lists_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro foreach(list, codeblock);
    %local i item count;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %unquote(%superq(codeblock))
    %end;
%mend foreach;

%macro transform(list, surrounded_by=, delimited_by=);
    %local i item count transformedList;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %let transformedList = &transformedList &surrounded_by&item&surrounded_by;
        %if &i < &count %then %let transformedList = &transformedList &delimited_by;
    %end;

    &transformedList.
%mend transform;

%macro len(list, delimiters=);
    %local count;
    %if %length(%superq(delimiters)) = 0 %then
        %let count = %sysfunc(countw(&list));
    %else
        %let count = %sysfunc(countw(&list, &delimiters));
    &count.
%mend len;

%macro nth(list, n);
    %local item;
    %let item = %scan(&list, &n);
    &item.
%mend nth;

%macro first(list);
    %local item;
    %let item = %nth(&list, 1);
    &item.
%mend first;

%macro last(list);
    %local count item;
    %let count = %len(&list);
    %let item = %nth(&list, &count);
    &item.
%mend last;

%macro unique(list);
    %local i item count uniqueList;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %if %length(%superq(uniqueList))=0 %then %do;
            %let uniqueList = &uniqueList &item;
        %end;
        %else %if %sysfunc(indexw(%superq(uniqueList), &item, %str( ))) = 0 %then %do;
            %let uniqueList = &uniqueList &item;
        %end;
    %end;

    &uniqueList.
%mend unique;

%macro sorted(list);
    %local i j count tmp;
    %let count = %len(&list);

    %if &count = 0 %then %do;

    %end;
    %else %do;
        %do i=1 %to &count;
            %let item&i=%scan(&list, &i, %str( ));
        %end;

        %do i=1 %to %eval(&count-1);
            %do j=%eval(&i+1) %to &count;
                %if %sysevalf(&&item&i > &&item&j) %then %do;
                    %let tmp=&&item&i;
                    %let item&i=&&item&j;
                    %let item&j=&tmp;
                %end;
            %end;
        %end;

        %local out;
        %let out=;
        %do i=1 %to &count;
            %let out=&out &&item&i;
        %end;
        %sysfunc(compbl(&out))
    %end;
%mend sorted;

%macro push(list, item);
    &list &item
%mend push;

%macro pop(list);
    %local count;
    %let count = %len(&list);
    %if &count <= 1 %then %do;

    %end;
    %else %do;
        %let list = %substr(&list, 1, %eval(%length(&list) - %length(%nth(&list, &count)) - 1));
        &list
    %end;
%mend pop;

%macro concat(list1, list2);
    &list1 &list2
%mend concat;

%macro list_err(type);
    %global has_err;
    %if &type.=len %then %put ERROR: The list is empty.;

    %let has_err = 1;
%mend list_err;

%macro test_lists;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing lists.sas);
        %test_case(list basics);
            %let list=a b c a;
            %assertEqual(%len(&list), 4);
            %assertEqual(%nth(&list, 2), b);
            %assertEqual(%first(&list), a);
            %assertEqual(%last(&list), a);
        %test_summary;

        %test_case(unique and concat);
            %let uniq=%unique(&list);
            %assertEqual(%len(&uniq), 3);
            %let combo=%concat(a b, c d);
            %assertEqual(&combo, a b c d);
        %test_summary;

        %test_case(unique avoids substring false positives);
            %let list2=a aa a;
            %let uniq2=%unique(&list2);
            %assertEqual(%sysfunc(compbl(&uniq2)), a aa);
        %test_summary;

        %test_case(sorted numeric list);
            %let nums=3 1 2;
            %let sorted=%sorted(&nums);
            %assertEqual(&sorted, 1 2 3);
        %test_summary;

        %test_case(transform and foreach);
            %let t=%transform(a b, surrounded_by=%str(%'), delimited_by=%str(,));
            %let t_comp=%sysfunc(compbl(%superq(t)));
            %assertEqual(%superq(t_comp), %str('a' , 'b'));

            %let acc=;
            %foreach(a b c, %nrstr(%let acc=&acc &item;));
            %assertEqual(%sysfunc(compbl(&acc)), a b c);
        %test_summary;

        %test_case(pop handles single item);
            %let p=%pop(a);
            %assertEqual(%length(&p), 0);
        %test_summary;

        %test_case(len with custom delimiters);
            %let l=a|b|c;
            %let lcount=%len(list=&l, delimiters=%str(|));
            %assertEqual(&lcount, 3);
        %test_summary;
    %test_summary;
%mend test_lists;

/* Macro to run lists tests when __unit_tests is set */
%macro run_lists_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_lists;
        %end;
    %end;
%mend run_lists_tests;

%run_lists_tests;
/* Caller: exercise list macros from src/lists.sas */
%test_suite(sassyverse lists compatibility check);
    %test_case(len nth first last);
        %let list=a b c d;
        %assertEqual(%len(&list), 4);
        %assertEqual(%nth(&list, 2), b);
        %assertEqual(%first(&list), a);
        %assertEqual(%last(&list), d);
    %test_summary;
    %test_case(concat and sorted);
        %let combo=%concat(a b, c d);
        %assertEqual(&combo, a b c d);
        %let nums=3 1 2;
        %let s=%sorted(&nums);
        %assertEqual(&s, 1 2 3);
    %test_summary;
    %test_case(transform quotes and delimits);
        %let t=%transform(a b, surrounded_by=%str(%'), delimited_by=%str(,));
        %let t_comp=%sysfunc(compbl(%superq(t)));
        %assertEqual(%superq(t_comp), %str('a' , 'b'));
    %test_summary;
%test_summary;
