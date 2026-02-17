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