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
- parmbuf_normalize_sep
- parmbuf_emit_token
- parmbuf_match_escaped_separator
- parmbuf_match_separator
- parmbuf_append_char
- parmbuf_parser
- test_parmbuf_parser
- run_parmbuf_parser_tests

7) Expected side effects from running/include
- Defines 3 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: parmbuf_parser, run_parmbuf_parser_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro parmbuf_normalize_sep(sep=, out_sep=parmbuf_sep, out_len=parmbuf_sep_len);
    %local _sep;
    %let _sep=%superq(sep);
    %if %length(%superq(_sep))=0 %then %let _sep=%str(,);
    %let &out_sep=%superq(_sep);
    %let &out_len=%length(%superq(_sep));
%mend;

%macro parmbuf_emit_token(out_prefix=param, index=1, token=);
    %global &out_prefix.&index;
    %let &out_prefix.&index=%superq(token);
%mend;

%macro parmbuf_match_escaped_separator(buf=, pos=, sep=, sep_len=, len=, out_append=, out_next_pos=, out_matched=);
    %local _buf _pos _maybe_sep _close;
    %let &out_matched=0;
    %let &out_append=;
    %let &out_next_pos=&pos;

    %let _buf=%superq(buf);
    %let _pos=%superq(pos);
    %if %eval(&_pos + &sep_len + 1) > &len %then %return;

    %let _maybe_sep=%qsubstr(&_buf, %eval(&_pos+1), &sep_len);
    %let _close=%qsubstr(&_buf, %eval(&_pos+1+&sep_len), 1);

    %if %superq(_maybe_sep)=%superq(sep) and %superq(_close)=%str(}) %then %do;
        %let &out_append=%superq(sep);
        %let &out_next_pos=%eval(&_pos + &sep_len + 2);
        %let &out_matched=1;
    %end;
%mend;

%macro parmbuf_match_separator(buf=, pos=, sep=, sep_len=, out_is_sep=0);
    %local _chunk;
    %let &out_is_sep=0;
    %if &sep_len=0 %then %return;
    %let _chunk=%qsubstr(%superq(buf), &pos, &sep_len);
    %if %superq(_chunk)=%superq(sep) %then %let &out_is_sep=1;
%mend;

%macro parmbuf_append_char(token=, char=, out_token=next_token);
    %let &out_token=%superq(token)%superq(char);
%mend;

%macro parmbuf_parser(parmbuf, sep=%str(,), out_prefix=param);
    %local buf sep_q seplen len i ch curr count esc_append next_pos esc_matched is_sep;

    %let buf=%superq(parmbuf);
    %parmbuf_normalize_sep(sep=%superq(sep), out_sep=sep_q, out_len=seplen);

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
            %parmbuf_match_escaped_separator(
                buf=%superq(buf),
                pos=&i,
                sep=%superq(sep_q),
                sep_len=&seplen,
                len=&len,
                out_append=esc_append,
                out_next_pos=next_pos,
                out_matched=esc_matched
            );

            %if &esc_matched %then %do;
                %parmbuf_append_char(token=%superq(curr), char=%superq(esc_append), out_token=curr);
                %let i=&next_pos;
            %end;
            %else %do;
                %parmbuf_append_char(token=%superq(curr), char=%superq(ch), out_token=curr);
                %let i=%eval(&i+1);
            %end;
        %end;
        %else %do;
            %parmbuf_match_separator(
                buf=%superq(buf),
                pos=&i,
                sep=%superq(sep_q),
                sep_len=&seplen,
                out_is_sep=is_sep
            );

            %if &is_sep %then %do;
                %parmbuf_emit_token(out_prefix=&out_prefix, index=&count, token=%superq(curr));
                %let count=%eval(&count+1);
                %let curr=;
                %let i=%eval(&i + &seplen);
            %end;
            %else %do;
                %parmbuf_append_char(token=%superq(curr), char=%superq(ch), out_token=curr);
                %let i=%eval(&i+1);
            %end;
        %end;
    %end;

    %parmbuf_emit_token(out_prefix=&out_prefix, index=&count, token=%superq(curr));
    %let &out_prefix._n=&count;
%mend;

%macro test_parmbuf_parser;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing parmbuf_parser helpers and orchestration);
        %test_case(normalize separator defaults and custom);
            %parmbuf_normalize_sep(sep=, out_sep=_sep1, out_len=_len1);
            %parmbuf_normalize_sep(sep=%str(|), out_sep=_sep2, out_len=_len2);
            %assertEqual(%superq(_sep1), %str(,));
            %assertEqual(&_len1, 1);
            %assertEqual(%superq(_sep2), %str(|));
            %assertEqual(&_len2, 1);
        %test_summary;

        %test_case(emit token writes globals);
            %parmbuf_emit_token(out_prefix=tst, index=5, token=hello);
            %assertEqual(%superq(tst5), hello);
        %test_summary;

        %test_case(match escaped separator succeeds and advances);
            %parmbuf_match_escaped_separator(
                buf=%str({,}x),
                pos=1,
                sep=%str(,),
                sep_len=1,
                len=4,
                out_append=_esc_app,
                out_next_pos=_esc_next,
                out_matched=_esc_match
            );
            %assertEqual(%superq(_esc_app), %str(,));
            %assertEqual(&_esc_next, 4);
            %assertEqual(&_esc_match, 1);
        %test_summary;

        %test_case(match escaped separator fails when pattern absent);
            %parmbuf_match_escaped_separator(
                buf=%str({x}),
                pos=1,
                sep=%str(,),
                sep_len=1,
                len=3,
                out_append=_esc_app2,
                out_next_pos=_esc_next2,
                out_matched=_esc_match2
            );
            %assertEqual(%length(%superq(_esc_app2)), 0);
            %assertEqual(&_esc_next2, 1);
            %assertEqual(&_esc_match2, 0);
        %test_summary;

        %test_case(match separator detects at position);
            %parmbuf_match_separator(buf=%str(a,b), pos=2, sep=%str(,), sep_len=1, out_is_sep=_sepflag);
            %assertEqual(&_sepflag, 1);
            %parmbuf_match_separator(buf=%str(ab), pos=1, sep=%str(,), sep_len=1, out_is_sep=_sepflag2);
            %assertEqual(&_sepflag2, 0);
        %test_summary;

        %test_case(append char concatenates safely);
            %parmbuf_append_char(token=a, char=%str(,), out_token=_tok);
            %assertEqual(%superq(_tok), %str(a,));
        %test_summary;

        %test_case(orchestrator basic parsing);
            %parmbuf_parser(%str(a,b,c), out_prefix=buf);
            %assertEqual(&buf_n, 3);
            %assertEqual(&buf1, a);
            %assertEqual(&buf2, b);
            %assertEqual(&buf3, c);
        %test_summary;

        %test_case(orchestrator escaped separator);
            %parmbuf_parser(%str(a{,}c), out_prefix=esc);
            %assertEqual(&esc_n, 1);
            %assertEqual(%superq(esc1), %str(a,c));
        %test_summary;

        %test_case(orchestrator empty tokens preserved);
            %parmbuf_parser(%str(a,,b,), out_prefix=emp);
            %assertEqual(&emp_n, 4);
            %assertEqual(&emp1, a);
            %assertEqual(%length(&emp2), 0);
            %assertEqual(&emp3, b);
            %assertEqual(%length(&emp4), 0);
        %test_summary;

        %test_case(orchestrator custom separator with escape);
            %parmbuf_parser(%str(a|b{|}c), sep=%str(|), out_prefix=bar);
            %assertEqual(&bar_n, 2);
            %assertEqual(&bar1, a);
            %assertEqual(&bar2, b|c);
        %test_summary;
    %test_summary;

    %symdel _sep1 _sep2 _len1 _len2 tst5 _esc_app _esc_next _esc_match _esc_app2 _esc_next2 _esc_match2 _sepflag _sepflag2 _tok
        buf1 buf2 buf3 buf_n esc1 esc_n emp1 emp2 emp3 emp4 emp_n bar1 bar2 bar_n / nowarn;
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