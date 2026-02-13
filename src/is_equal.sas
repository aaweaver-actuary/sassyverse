%MACRO is_equal(a, b);
    %local out a_val b_val is_num;
    
    /* Check if parameters are provided */
    %if %superq(a)= OR %superq(b)= %then %do;
        %put ERROR: Both parameters are required.;
        %return(0);
    %end;

    /* Try numeric comparison first */
    %let is_num=%sysfunc(verify(%superq(a),%str(0123456789.+-eE)));
    %if &is_num=0 %then %do;
        %let a_val=%sysevalf(%superq(a));
        %let b_val=%sysevalf(%superq(b));
        %if (&a_val=&b_val) %then %let out=1;
        %else %let out=0;
    %end;
    %else %do;
        /* Character comparison */
        %if %superq(a)=%superq(b) %then %let out=1;
        %else %let out=0;
    %end;

    &out
%MEND is_equal;

%MACRO is_not_equal(a, b);
	%let opposite=%is_equal(&a., &b.);
	%if &opposite=1 %then %let out=0;
	%else %let out=1;

	&out
%MEND is_not_equal;