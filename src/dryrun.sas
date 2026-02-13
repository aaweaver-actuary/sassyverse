%macro dryrun(macro_name, args);
    %local result resolved_macro;

    /* Attempt to resolve the macro call */
    %let resolved_macro=%nrstr(&&macro_name(&args));

    /* Check for unmatched quotation marks */
    %if %index(&resolved_macro, %str(%')) ne %index(&resolved_macro, %str(%'))
        %then %do;
        %put ERROR: Unmatched single quotation marks in the macro call.;
        %return;
    %end;
    %if %index(&resolved_macro, %str(%")) ne %index(&resolved_macro, %str(%"))
        %then %do;
        %put ERROR: Unmatched double quotation marks in the macro call.;
        %return;
    %end;

    /* Resolve the macro call */
    %let result=%sysfunc(resolve(&resolved_macro));

    /* Handle potential errors during resolution */
    %if &syserr ne 0 %then %do;
        %put ERROR: An error occurred while resolving the macro call.;
        %put ERROR: (&syserror.) &syserrortext.;
        %return;
    %end;

    /* Print the resolved macro call to the log */
    %put &result;
%mend dryrun;

%sbmod(logger);

%info(can I log x1);
%put %dryrun(info, can i log x2);
