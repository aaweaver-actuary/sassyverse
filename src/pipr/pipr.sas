%include 'validation.sas';
%include 'utils.sas';

%macro pipe(
  data=,
  out=,
  steps=,
  validate=1,
  use_views=1,
  view_output=0,
  debug=0,
  cleanup=1
);
  %local i n cur nxt tmp1 tmp2 step verb args supports_view as_view final_as_view;

  %_assert_ds_exists(&data, msg=Input to pipe() is missing.);
  %if %length(&steps)=0 %then %_abort(pipe() requires steps= delimited by '|'.);

  %let tmp1=%_tmpds(prefix=_p1_);
  %let tmp2=%_tmpds(prefix=_p2_);
  %let cur=&data;

  %let n=%sysfunc(countw(&steps, |, m));
  %if &n = 0 %then %_abort(pipe() requires steps= delimited by '|'.);

  %do i=1 %to &n;
    %let step=%scan(&steps, &i, |, m);

    %let verb=%scan(&step, 1, %str(%());
    %if %length(&verb)=0 %then %_abort(Bad step token: &step);

    %let supports_view=%_verb_supports_view(&verb);

    /* Plan whether this step writes a view:
       - only if use_views=1
       - only if verb supports it
       - if this is final step: only if view_output=1, else materialize */
    %if &i = &n %then %do;
      %let final_as_view=%sysfunc(ifc((&view_output=1) and (&supports_view>0), 1, 0));
      %let as_view=&final_as_view;
      %let nxt=&out;
    %end;
    %else %do;
      %let as_view=%sysfunc(ifc((&use_views=1) and (&supports_view>0), 1, 0));
      %let nxt=%sysfunc(ifc(%sysevalf(mod(&i,2)=1), &tmp1, &tmp2));
    %end;

    %if &debug %then %do;
      %put NOTE: PIPE step &i/&n: &step;
      %put NOTE:   verb=&verb supports_view=&supports_view planned_as_view=&as_view;
      %put NOTE:   in=&cur;
      %put NOTE:   out=&nxt;
    %end;

    %_apply_step(&step, &cur, &nxt, &validate, &as_view);

    %_assert_ds_exists(&nxt, msg=Step &i did not create expected output. Step token: &step);
    %let cur=&nxt;
  %end;

  %if &cleanup %then %do;
    /* Delete temps (views or tables) if they are not the final output */
    %if %upcase(&tmp1) ne %upcase(&out) %then %do;
      proc datasets lib=work nolist; delete %scan(&tmp1,2,.); quit;
    %end;
    %if %upcase(&tmp2) ne %upcase(&out) %then %do;
      proc datasets lib=work nolist; delete %scan(&tmp2,2,.); quit;
    %end;
  %end;
%mend;