/* 
    Abort the SAS session with a given error message.
    Usage: %_abort(Some error occurred)
*/
%macro _abort(msg);
  %put ERROR: &msg;
  %abort cancel;
%mend;


/* 
    Generate a temporary dataset name with a given prefix. The name is based on the current datetime to ensure uniqueness.
    Usage: %_tmpds(prefix=mytemp_)
*/
%macro _tmpds(prefix=_p);
  %sysfunc(cats(work., &prefix., %sysfunc(putn(%sysfunc(datetime()), hex16.))))
%mend;

%macro test_pipr_util;
  %sbmod(assert);

  %test_suite(Testing pipr util);
    %test_case(tmpds uses prefix and work);
      %let t=%_tmpds(prefix=_t_);
      %assertTrue(%eval(%index(&t, work._t_) = 1), tmpds starts with work._t_);
    %test_summary;
  %test_summary;
%mend test_pipr_util;

%test_pipr_util;