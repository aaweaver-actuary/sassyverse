%macro dryrun(macro_name, args);
    %local result resolved_macro sq dq;

    /* Attempt to resolve the macro call */
    %let resolved_macro=%nrstr(%)&macro_name(%superq(args));

    /* Check for unmatched quotation marks */
    %let sq=%sysfunc(countc(%superq(resolved_macro), %str(%')));
    %if %sysfunc(mod(&sq, 2)) ne 0 %then %do;
        %put ERROR: Unmatched single quotation marks in the macro call.;
        %return;
    %end;
    %let dq=%sysfunc(countc(%superq(resolved_macro), %str(%")));
    %if %sysfunc(mod(&dq, 2)) ne 0 %then %do;
        %put ERROR: Unmatched double quotation marks in the macro call.;
        %return;
    %end;

    /* Resolve the macro call in a data step */
    data _null_;
        length _res $ 32767;
        _res = resolve(symget('resolved_macro'));
        call symputx('result', _res, 'L');
    run;

    /* Handle potential errors during resolution */
    %if &syserr ne 0 %then %do;
        %put ERROR: An error occurred while resolving the macro call.;
        %put ERROR: (&syserror.) &syserrortext.;
        %return;
    %end;

    /* Print the resolved macro call to the log */
    %put &result;
    &result
%mend dryrun;

%macro test_dryrun;
    %sbmod(assert);

    %test_suite(Testing dryrun);
        %test_case(dryrun returns resolved macro call);
            %macro __dryrun_echo(x); &x %mend;
            %let out=%dryrun(__dryrun_echo, 123);
            %assertEqual(&out., 123);
        %test_summary;
    %test_summary;
%mend test_dryrun;

%test_dryrun;
