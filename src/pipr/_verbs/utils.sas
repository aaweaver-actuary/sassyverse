%macro _verb_positional_list;
  FILTER MUTATE ARRANGE KEEP DROP SELECT RENAME SUMMARISE SUMMARIZE
  WHERE WHERE_NOT MASK WHERE_IF SORT
  LEFT_JOIN INNER_JOIN LEFT_JOIN_HASH INNER_JOIN_HASH LEFT_JOIN_SQL INNER_JOIN_SQL
  COLLECT_TO COLLECT_INTO
%mend;

%macro _verb_view_supported_list;
  FILTER MUTATE KEEP DROP
  LEFT_JOIN INNER_JOIN LEFT_JOIN_HASH INNER_JOIN_HASH LEFT_JOIN_SQL INNER_JOIN_SQL
  SELECT RENAME WHERE WHERE_NOT MASK WHERE_IF
  COLLECT_TO COLLECT_INTO
%mend;

%macro _is_positional_verb(verb);
  %local v;
  %let v=%upcase(&verb);
  %sysfunc(indexw(%_verb_positional_list, &v))
%mend;

%macro _verb_supports_view(verb);
  %local v;
  %let v=%upcase(&verb);
  /* arrange/summarise cannot; left_join can */
  %sysfunc(indexw(%_verb_view_supported_list, &v))
%mend;

%macro _step_parse(step, out_verb, out_args);
  %local verb args paren_pos;

  %global &out_verb &out_args;

  %let verb=%scan(%superq(step), 1, %str(%());
  %if %length(&verb)=0 %then %_abort(Bad step token (missing verb): &step);

  %let paren_pos=%index(%superq(step), %str(%());
  %if &paren_pos > 0 %then %do;
    %let args=%substr(%superq(step), %eval(&paren_pos+1));
    %if %length(%superq(args)) %then %do;
      %let args=%substr(%superq(args), 1, %eval(%length(%superq(args))-1));
    %end;
  %end;
  %else %let args=;

  %let &out_verb=&verb;
  %let &out_args=%superq(args);
%mend;

%macro _step_has_validate(args, out_has);
  %local has;
  %global &out_has;
  %let has=%sysfunc(index(%upcase(%superq(args)), VALIDATE=));
  %let &out_has=&has;
%mend;

%macro _step_call_positional(verb, args, in, out, as_view, pipe_validate, has_validate);
  %if %length(%superq(args)) %then %do;
    %unquote(%nrstr(%)&verb)(
      %nrstr(%bquote(&args)),
      data=&in,
      out=&out,
      as_view=&as_view
      %sysfunc(ifc(&has_validate, %str(), %str(, validate=&pipe_validate)))
    );
  %end;
  %else %do;
    %unquote(%nrstr(%)&verb)(
      ,
      data=&in,
      out=&out,
      as_view=&as_view
      %sysfunc(ifc(&has_validate, %str(), %str(, validate=&pipe_validate)))
    );
  %end;
%mend;

%macro _step_call_named(verb, args, in, out, as_view, pipe_validate, has_validate);
  %if %length(%superq(args)) %then %do;
    %unquote(%nrstr(%)&verb)(
      data=&in,
      out=&out,
      &args,
      as_view=&as_view
      %sysfunc(ifc(&has_validate, %str(), %str(, validate=&pipe_validate)))
    );
  %end;
  %else %do;
    %unquote(%nrstr(%)&verb)(
      data=&in,
      out=&out,
      as_view=&as_view
      %sysfunc(ifc(&has_validate, %str(), %str(, validate=&pipe_validate)))
    );
  %end;
%mend;

/* step expansion with:
   - automatic quoting for positional argument: %bquote(&args)
   - injection of data/out/validate
   - injection of as_view= (planned per step)
*/
%macro _apply_step(step, in, out, pipe_validate, as_view);
  %local is_pos;

  %_step_parse(%superq(step), _pipe_step_verb, _pipe_step_args);
  %let is_pos=%_is_positional_verb(&_pipe_step_verb);
  %_step_has_validate(&_pipe_step_args, _pipe_has_validate);

  %if &is_pos %then %do;
    /* Positional verbs: first arg auto-quoted to protect commas */
    %_step_call_positional(&_pipe_step_verb, &_pipe_step_args, &in, &out, &as_view, &pipe_validate, &_pipe_has_validate);
  %end;
  %else %do;
    /* Named-args verbs: args come after injected params */
    %_step_call_named(&_pipe_step_verb, &_pipe_step_args, &in, &out, &as_view, &pipe_validate, &_pipe_has_validate);
  %end;
%mend;

%macro test_pipr_verb_utils;
  %_pipr_require_assert;
  %global _sp_verb _sp_args _sp_has;

  %test_suite(Testing pipr verb utils);
    %test_case(positional and view support flags);
      %assertTrue(%eval(%_is_positional_verb(filter) > 0), filter is positional);
      %assertTrue(%eval(%_is_positional_verb(rename) > 0), rename is positional);
      %assertTrue(%eval(%_is_positional_verb(select) > 0), select is positional);
      %assertTrue(%eval(%_is_positional_verb(summarise) > 0), summarise is positional);
      %assertTrue(%eval(%_is_positional_verb(left_join) > 0), left_join is positional);
      %assertTrue(%eval(%_is_positional_verb(collect_to) > 0), collect_to is positional);
      %assertTrue(%eval(%_verb_supports_view(filter) > 0), filter supports views);
      %assertTrue(%eval(%_verb_supports_view(select) > 0), select supports views);
      %assertTrue(%eval(%_verb_supports_view(rename) > 0), rename supports views);
      %assertTrue(%eval(%_verb_supports_view(arrange) = 0), arrange does not support views);
    %test_summary;

    %test_case(step parse and validate flag);
      %_step_parse(%str(filter(x > 1)), _sp_verb, _sp_args);
      %_step_has_validate(&_sp_args, _sp_has);
      %assertEqual(&_sp_verb., filter);
      %assertEqual(&_sp_args., x > 1);
      %assertEqual(&_sp_has., 0);

      %_step_parse(%str(select(x)), _sp_verb, _sp_args);
      %_step_has_validate(&_sp_args, _sp_has);
      %assertEqual(&_sp_verb., select);
      %assertEqual(&_sp_args., x);
      %assertEqual(&_sp_has., 0);
    %test_summary;

    %test_case(apply_step with filter);
      data work._ut_in;
        x=1; output;
        x=2; output;
        x=3; output;
      run;

      %_apply_step(%str(filter(x > 1)), work._ut_in, work._ut_out, 1, 0);

      proc sql noprint;
        select count(*) into :_ut_cnt trimmed from work._ut_out;
      quit;

      %assertEqual(&_ut_cnt., 2);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _ut_in _ut_out; quit;
%mend test_pipr_verb_utils;

%_pipr_autorun_tests(test_pipr_verb_utils);
