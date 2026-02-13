%macro _summarise_run(vars, stats, by=, data=, out=);
  proc summary data=&data nway;
    %if %length(%superq(by)) %then %do; class &by; %end;
    var &vars;
    output out=&out(drop=_type_ _freq_) &stats;
  run;
%mend;

%macro summarise(vars, by=, data=, out=, stats=, validate=1, as_view=0);
  %_assert_ds_exists(&data);
  %if %length(&vars)=0 %then %_abort(summarise() requires vars=);
  %if %length(&stats)=0 %then %_abort(summarise() requires stats=);
  %if &as_view %then %_abort(summarise() does not support as_view=1);

  %if &validate %then %do;
    %_assert_cols_exist(&data, &vars);
    %if %length(&by) %then %_assert_cols_exist(&data, &by);
  %end;

  %_summarise_run(vars=&vars, stats=&stats, by=&by, data=&data, out=&out);

  %if &syserr > 4 %then %_abort(summarise() failed (SYSERR=&syserr).);
%mend summarise;

%macro summarize(vars, by=, data=, out=, stats=, validate=1, as_view=0);
  %summarise(vars=&vars, by=&by, data=&data, out=&out, stats=&stats, validate=&validate, as_view=&as_view);
%mend summarize;

%macro test_summarise;
  %sbmod(assert);

  %test_suite(Testing summarise);
    %test_case(summarise aggregates by group);
      data work._sum;
        grp='A'; x=1; output;
        grp='A'; x=3; output;
        grp='B'; x=2; output;
      run;

      %summarise(
        vars=x,
        by=grp,
        data=work._sum,
        out=work._sum_out,
        stats=mean=avg sum=total
      );

      proc sql noprint;
        select avg into :_avg_a trimmed from work._sum_out where grp='A';
        select total into :_total_b trimmed from work._sum_out where grp='B';
      quit;

      %assertEqual(&_avg_a., 2);
      %assertEqual(&_total_b., 2);
    %test_summary;

    %test_case(summarize alias works);
      %summarize(
        vars=x,
        by=,
        data=work._sum,
        out=work._sum_out2,
        stats=mean=avg
      );

      proc sql noprint;
        select avg into :_avg_all trimmed from work._sum_out2;
      quit;

      %assertEqual(&_avg_all., 2);
    %test_summary;

    %test_case(summarise helper no by);
      %_summarise_run(vars=x, stats=sum=total, by=, data=work._sum, out=work._sum_helper);

      proc sql noprint;
        select total into :_total_helper trimmed from work._sum_helper;
      quit;

      %assertEqual(&_total_helper., 6);
    %test_summary;
  %test_summary;

  proc datasets lib=work nolist; delete _sum _sum_out _sum_out2 _sum_helper; quit;
%mend test_summarise;

%test_summarise;