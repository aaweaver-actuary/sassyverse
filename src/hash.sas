/* MODULE DOC
File: src/hash.sas

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
- _hash_bootstrap
- hash__dcl
- hash__key
- hash__data
- hash__done
- hash__missing
- hash__add
- _get_char_vars
- _one_char_length_stmnt
- make_hash_obj
- test_hash_macros
- run_hash_tests

7) Expected side effects from running/include
- Defines 12 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: _hash_bootstrap, run_hash_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro _hash_bootstrap;
    %if not %sysmacexist(str__replace) %then %sbmod(strings);
%mend _hash_bootstrap;

%_hash_bootstrap;

%macro hash__dcl(
	hashObj /* Variable representing the hash object */
	, dataset= /* Optional keyword variable for passing a dataset to the hash object constructor */
	, ordered= /* Optional keyword variable for passing an order */
);
    %if %length(&dataset.)=0 %then
        %let out=dcl hash &hashObj.();
    %else
        %let out=dcl hash &hashObj.(dataset: "&dataset.");
    &out.
%mend hash__dcl;

%macro hash__key(hashObj, cols, isOne=0);
    %if &isOne.=1 %then
        %let keyList="&cols.";
    %else %do;
        %do i=1 %to %sysfunc(countw(&cols.));
            %let cur=%scan(&cols., &i.);
            %if &i.=1 %then
                %let keyList="&cur.";
            %else
                %let keyList=&keyList., "&cur.";
        %end;
    %end;

    &hashObj..defineKey(&keyList.);
%mend hash__key;

%macro hash__data(hashObj, cols, isOne=0);
    %if &isOne.=1 %then
        %let dataList="&cols.";
    %else %do;
        %do i=1 %to %sysfunc(countw(&cols.));
            %let cur=%scan(&cols., &i.);
            %if &i.=1 %then
                %let dataList="&cur.";
            %else
                %let dataList=&dataList., "&cur.";
        %end;
    %end;

    &hashObj..defineData(&dataList.);
%mend hash__data;

%macro hash__done(hashObj);
    &hashObj..defineDone();
%mend hash__done;

%macro hash__missing(hashObj, cols, isOne=0);
    %if &isOne.=1 %then
        %let missingList=&cols.;
    %else %do;
        %do i=1 %to %sysfunc(countw(&cols.));
            %let cur=%scan(&cols., &i.);
            %if &i.=1 %then
                %let missingList=&cur.;
            %else
                %let missingList=&missingList., &cur.;
        %end;
    %end;

    call missing(&missingList.);
%mend hash__missing;

%macro hash__add(hashObj, key, value);
    &hashObj..add(key: "&key.", data: "&value.");
%mend hash__add;

%macro _get_char_vars(char);
        %put char: &char;
    %let items=%str__replace(&char., |, %str( ) );
    %let nItems=%sysfunc(countw(&items., %str( )));
    %let nPairs=%eval(&nItems. / 2);
        %put nPairs: &nPairs.;
    %if %length(&nPairs.)>1 %then %do;
        %do i=1 %to %length(&char.);
            %let cur=%scan(&char., &i., ' ');
            %_one_char_length_stmnt(&cur.);
        %end;
    %end;
    %else %do;
        %_one_char_length_stmnt(&char.);
    %end;
%mend _get_char_vars;

%macro _one_char_length_stmnt(current);
    %let var=%scan(&current., 1, '|');
    %let len=%scan(&current., 2, '|');
    length &var. $ &len.;
%mend _one_char_length_stmnt;

%macro make_hash_obj(hashObj, key=, num=, char=, dataset=, isOne=0);
    %if %length(&num.)>0 %then %do;
        length &num. 8.;
    %end;

    %hash__dcl(&hashObj., dataset=&dataset.);
    %hash__key(&hashObj., &key., isOne=&isOne.);

%mend make_hash_obj;

%macro test_hash_macros;
%if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then %do;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(hash.sas macro tests);
        %let charVarsFromOneCharLenStmnt=%_one_char_length_stmnt( singleVar|5 );
        %assertEqual("&charVarsFromOneCharLenStmnt.", "length singleVar $ 5;");

        %let dcl1=%hash__dcl(h);
        %assertEqual("&dcl1.", "dcl hash h()");

        %let dcl2=%hash__dcl(h, dataset=work.ds);
        %let exp_dcl2=%nrstr(dcl hash h(dataset: "work.ds"));
        %assertEqual(%superq(dcl2), %superq(exp_dcl2));

        %let key1=%hash__key(h, id, isOne=1);
        %let exp_key1=%nrstr(h.defineKey("id"););
        %assertEqual(%superq(key1), %superq(exp_key1));

        %let key2=%hash__key(h, %str(id grp), isOne=0);
        %let exp_key2=%nrstr(h.defineKey("id", "grp"););
        %assertEqual(%superq(key2), %superq(exp_key2));

        %let data1=%hash__data(h, r1, isOne=1);
        %let exp_data1=%nrstr(h.defineData("r1"););
        %assertEqual(%superq(data1), %superq(exp_data1));

        %let data2=%hash__data(h, %str(r1 r2), isOne=0);
        %let exp_data2=%nrstr(h.defineData("r1", "r2"););
        %assertEqual(%superq(data2), %superq(exp_data2));

        %let miss1=%hash__missing(h, miss_a, isOne=1);
        %let exp_miss1=%nrstr(call missing(miss_a););
        %assertEqual(%superq(miss1), %superq(exp_miss1));

        %let miss2=%hash__missing(h, %str(miss_a miss_b), isOne=0);
        %let exp_miss2=%nrstr(call missing(miss_a, miss_b););
        %assertEqual(%superq(miss2), %superq(exp_miss2));

        %let add1=%hash__add(h, id, value);
        %let exp_add1=%nrstr(h.add(key: "id", data: "value"););
        %assertEqual(%superq(add1), %superq(exp_add1));

/*        %let charVarsFromGetCharVars=%_get_char_vars( singleVar|5 );*/
/*        %assertEqual("&charVarsFromGetCharVars.", "length singleVar $ 5;");*/
    %test_summary;

    %end;
%end;
%mend test_hash_macros;

/* Macro to run hash tests when __unit_tests is set */
%macro run_hash_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_hash_macros;
        %end;
    %end;
%mend run_hash_tests;

%run_hash_tests;
