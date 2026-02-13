%macro _is_positional_verb(verb);
  %local v;
  %let v=%upcase(&verb);
  %sysfunc(indexw(FILTER MUTATE ARRANGE KEEP DROP, &v))
%mend;

%macro _verb_supports_view(verb);
  %local v;
  %let v=%upcase(&verb);
  /* arrange/summarise cannot; left_join_hash can */
  %sysfunc(indexw(FILTER MUTATE KEEP DROP LEFT_JOIN_HASH, &v))
%mend;

/* step expansion with:
   - automatic quoting for positional argument: %bquote(&args)
   - injection of data/out/validate
   - injection of as_view= (planned per step)
*/
%macro _apply_step(step, in, out, pipe_validate, as_view);
  %local verb args has_validate is_pos;

  %let verb=%scan(&step, 1, %str(%());
  %if %length(&verb)=0 %then %_abort(Bad step token (missing verb): &step);

  %let args=%substr(&step, %eval(%length(&verb)+2));
  %let args=%substr(&args, 1, %eval(%length(&args)-1));

  %let is_pos=%_is_positional_verb(&verb);
  %let has_validate=%sysfunc(index(%upcase(&args), VALIDATE=));

  %if &is_pos %then %do;
    /* Positional verbs: first arg auto-quoted to protect commas */
    %if %length(&args) %then %do;
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
  %end;
  %else %do;
    /* Named-args verbs: args come after injected params */
    %if %length(&args) %then %do;
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
  %end;
%mend;