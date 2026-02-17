/* MODULE DOC
File: src/buffer.sas

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
- parmbuf_parser
- test_parmbuf_parser
- run_parmbuf_parser_tests

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: parmbuf_parser, run_parmbuf_parser_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
/*
    Parses the parameter buffer from a macro call into individual parameters.
    For example, if parmbuf is "a,b,c", sep is ",", and out_prefix is "param", this
    macro will create macro variables &param1=a, &param2=b, and &param3=c,
    plus &param_n=3.

    Since "," is the separator by default, if a comma is needed as a literal in the
    parameters, the caller should wrap the comma in {}, eg

    %parmbuf_parser(a{,}c)
     will create &param1=a,c -- not 2 parameters but 1 parameter with a literal comma separating a and c.
*/
%macro parmbuf_parser(parmbuf, sep=%str(,), out_prefix=param);
    %local buf sep_q seplen len i ch maybe_sep close curr count esc;

    %let buf=%superq(parmbuf);
    %let sep_q=%superq(sep);
    %if %length(&sep_q)=0 %then %let sep_q=%str(,);
    %let seplen=%length(&sep_q);

    %global &out_prefix._n;
    %if %length(%superq(buf))=0 %then %do;
        %let &out_prefix._n=0;
        %return;
    %end;

    %let len=%length(&buf);
    %let count=1;
    %let curr=;
    %let i=1;

    %do %while(&i <= &len);
        %let ch=%qsubstr(&buf, &i, 1);

        %if %superq(ch)=%str({) %then %do;
            %let esc=0;
            %if &seplen > 0 %then %do;
                %if %eval(&i + &seplen + 1) <= &len %then %do;
                    %let maybe_sep=%qsubstr(&buf, %eval(&i+1), &seplen);
                    %let close=%qsubstr(&buf, %eval(&i+1+&seplen), 1);
                    %if %superq(maybe_sep)=%superq(sep_q) and %superq(close)=%str(}) %then %do;
                        %let curr=%superq(curr)%superq(sep_q);
                        %let i=%eval(&i + &seplen + 2);
                        %let esc=1;
                    %end;
                %end;
            %end;

            %if &esc=0 %then %do;
                %let curr=%superq(curr)%superq(ch);
                %let i=%eval(&i+1);
            %end;
        %end;
        %else %if &seplen > 0 %then %do;
            %let maybe_sep=%qsubstr(&buf, &i, &seplen);
            %if %superq(maybe_sep)=%superq(sep_q) %then %do;
                %global &out_prefix.&count;
                %let &out_prefix.&count=%superq(curr);
                %let count=%eval(&count+1);
                %let curr=;
                %let i=%eval(&i + &seplen);
            %end;
            %else %do;
                %let curr=%superq(curr)%superq(ch);
                %let i=%eval(&i+1);
            %end;
        %end;
        %else %do;
            %let curr=%superq(curr)%superq(ch);
            %let i=%eval(&i+1);
        %end;
    %end;

    %global &out_prefix.&count;
    %let &out_prefix.&count=%superq(curr);
    %let &out_prefix._n=&count;
%mend;

%macro test_parmbuf_parser;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing parmbuf_parser);
        %test_case(basic parsing);
            %parmbuf_parser(%str(a,b,c), out_prefix=buf);
            %assertEqual(&buf_n, 3);
            %assertEqual(&buf1, a);
            %assertEqual(&buf2, b);
            %assertEqual(&buf3, c);
        %test_summary;

        %test_case(escaped separator);
            %parmbuf_parser(%str(a{,}c), out_prefix=esc);
            %assertEqual(&esc_n, 1);
            %assertEqual(%superq(esc1), %str(a,c));
        %test_summary;

        %test_case(empty tokens preserved);
            %parmbuf_parser(%str(a,,b,), out_prefix=emp);
            %assertEqual(&emp_n, 4);
            %assertEqual(&emp1, a);
            %assertEqual(%length(&emp2), 0);
            %assertEqual(&emp3, b);
            %assertEqual(%length(&emp4), 0);
        %test_summary;

        %test_case(custom separator with escape);
            %parmbuf_parser(%str(a|b{|}c), sep=%str(|), out_prefix=bar);
            %assertEqual(&bar_n, 2);
            %assertEqual(&bar1, a);
            %assertEqual(&bar2, b|c);
        %test_summary;
    %test_summary;

    %symdel buf1 buf2 buf3 buf_n esc1 esc_n emp1 emp2 emp3 emp4 emp_n bar1 bar2 bar_n / nowarn;
%mend test_parmbuf_parser;

/* Macro to run buffer tests when __unit_tests is set */
%macro run_parmbuf_parser_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_parmbuf_parser;
        %end;
    %end;
%mend run_parmbuf_parser_tests;

%run_parmbuf_parser_tests;