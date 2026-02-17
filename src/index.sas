/* MODULE DOC
File: src/index.sas

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
- make_simple_indices
- make_simple_index
- make_comp_index
- create_simple_indices
- create_simple_index
- test_index_macros
- run_index_tests

7) Expected side effects from running/include
- Defines 7 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_index_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro make_simple_indices(
    ds /* The dataset to make the index on */
    , col /* A space-separated list of column names to make indices on */
    , lib /* Libref (optional). Defaults to WORK */
);
    %if %length(&lib.)=0 %then
        %let library=work;
    %else %let library=&lib.;

    %if %length(&col.) = 1 %then %do;
        %make_simple_index(&ds., &col., &lib.);
    %end;
    %else %do;
        %do i=1 %to %sysfunc(countw(&col.));
            %let cur=%scan(&col., &i.);
            %make_simple_index(&ds., &cur., &lib.);
        %end;
    %end;
%mend make_simple_indices;

%macro make_simple_index(ds, col, lib);
    %if %length(&lib.)=0 %then
        %let library=work;
    %else %let library=&lib.;

    proc datasets
        library=&library.
        nodetails nolist nowarn;
        sysecho "Adding index on the column &col. in &library..&ds.";
        modify &ds.;
            index create &col.;
        run;
    quit;
%mend make_simple_index;

%macro make_comp_index(ds, col, lib);
    %if %length(&lib.)=0 %then
        %let library=work;
    %else %let library=&lib.;

    %local compkey;
    %do i=1 %to %sysfunc(countw(&col.));
        %let cur=%scan(&col., &i.);
        %if &i.=1 %then
            %let compkey=&cur.;
        %else
            %let compkey=&compkey.&cur.;
    %end;

    proc datasets
        library=&library.
        nodetails nolist nowarn;
        sysecho "Adding composite index keyed by &col. in &library..&ds.";
        modify &ds.;
            index create &compkey.=(&col.);
        run;
    quit;
%mend make_comp_index;

/* The following macros alias the macros from above. I made the
mistake of forgetting the actual name one too many times.    */

%macro create_simple_indices(
    ds /* The dataset to make the index on */
    , col /* A space-separated list of column names to make indices on */
    , lib /* Libref (optional). Defaults to WORK */
);
    %if %length(&lib.) > 0 %then %do;
        %make_simple_indices(&ds., &col., &lib.)
    %end;
    %else %do;
        %make_simple_indices(&ds., &col.)
    %end;
%mend create_simple_indices;

%macro create_simple_index(
          ds /* The dataset to make the index on */
        , col /* A single column name from the dataset */
        , lib /* Libref (optional). Defaults to WORK */
    );
    %if %length(&lib.) > 0 %then %do;
        %make_simple_index(&ds., &col., &lib.)
    %end;
    %else %do;
        %make_simple_index(&ds., &col.)
    %end;
%mend create_simple_index;

%macro test_index_macros;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing index helpers);
        %test_case(make_simple_index creates index);
            data work.test_index;
                x=1; y=10; output;
                x=2; y=20; output;
            run;

            %make_simple_index(test_index, x, work);

            proc sql noprint;
                select count(*) into :_idx_cnt trimmed
                from sashelp.vindex
                where libname="WORK" and memname="TEST_INDEX" and upcase(name)="X";
            quit;

            %assertTrue(%eval(&_idx_cnt > 0), index created on X);
        %test_summary;

        %test_case(make_simple_indices supports multi-column list);
            %make_simple_indices(test_index, x y, work);

            proc sql noprint;
                select count(*) into :_idx_xy_cnt trimmed
                from sashelp.vindex
                where libname="WORK" and memname="TEST_INDEX" and upcase(name) in ("X","Y");
            quit;

            %assertTrue(%eval(&_idx_xy_cnt >= 2), indices created on X and Y);
        %test_summary;

        %test_case(make_comp_index creates composite key index);
            %make_comp_index(test_index, x y, work);

            proc sql noprint;
                select count(*) into :_idx_comp_cnt trimmed
                from sashelp.vindex
                where libname="WORK" and memname="TEST_INDEX" and upcase(name)="XY";
            quit;

            %assertTrue(%eval(&_idx_comp_cnt > 0), composite index created);
        %test_summary;

        %test_case(alias helpers call index creators with optional lib);
            %create_simple_index(test_index, x);
            %create_simple_indices(test_index, y);

            proc sql noprint;
                select count(*) into :_idx_alias_cnt trimmed
                from sashelp.vindex
                where libname="WORK" and memname="TEST_INDEX" and upcase(name) in ("X","Y");
            quit;

            %assertTrue(%eval(&_idx_alias_cnt >= 2), alias helpers created expected indexes);
        %test_summary;

        %test_case(alias helpers accept explicit lib argument);
            %create_simple_index(test_index, x, work);
            %create_simple_indices(test_index, y, work);

            proc sql noprint;
                select count(*) into :_idx_alias_lib_cnt trimmed
                from sashelp.vindex
                where libname="WORK" and memname="TEST_INDEX" and upcase(name) in ("X","Y");
            quit;

            %assertTrue(%eval(&_idx_alias_lib_cnt >= 2), alias helpers with lib created expected indexes);
        %test_summary;
    %test_summary;

    proc datasets lib=work nolist; delete test_index; quit;
%mend test_index_macros;

/* Macro to run index tests when __unit_tests is set */
%macro run_index_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_index_macros;
        %end;
    %end;
%mend run_index_tests;

%run_index_tests;
