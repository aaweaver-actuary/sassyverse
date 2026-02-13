%macro filter(where_expr, data=, out=, validate=1, as_view=0);
  %_assert_ds_exists(&data);

  %if &as_view %then %do;
    data &out / view=&out;
      set &data;
      %if %length(&where_expr) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;
  %else %do;
    data &out;
      set &data;
      %if %length(&where_expr) %then %do;
        if (&where_expr);
      %end;
    run;
  %end;

  %if &syserr > 4 %then %_abort(filter() failed (SYSERR=&syserr).);
%mend;

%macro where(where_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=&where_expr, data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro where_not(where_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=not (&where_expr), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro mask(mask_expr, data=, out=, validate=1, as_view=0);
  %filter(where_expr=not (&mask_expr), data=&data, out=&out, validate=&validate, as_view=&as_view);
%mend;

%macro where_if(where_expr, condition, data=, out=, validate=1, as_view=0);
  %if &condition %then %do;
    %filter(where_expr=&where_expr, data=&data, out=&out, validate=&validate, as_view=&as_view);
  %end;
  %else %do;
    %filter(where_expr=, data=&data, out=&out, validate=&validate, as_view=&as_view);
  %end;
%mend;