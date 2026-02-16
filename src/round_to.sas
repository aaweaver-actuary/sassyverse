%if %sysfunc(libref(sbfuncs)) ne 0 %then %do;
  libname sbfuncs "%sysfunc(pathname(work))";
%end;


proc fcmp 
	outlib=sbfuncs.fn.math;
	
	function roundto(x, n_digits);
		N = 10 ** n_digits;
		return( round(N * x)/N );
	endsub;
run;

%macro roundto(
    x /* Value to round */
    , n_digits /* Number of digits to round to. Defaults to 0. */
);
    %if %length(%superq(n_digits))=0 
        %then %let n_digits=0;

    %let n=%eval(10 ** &n_digits.);
    %let prod=%sysevalf(&n. * &x.);
    %let out=%sysfunc(round(&prod.));
    %let out=%sysevalf(&out. / &n.);
    &out.
%mend roundto;

%macro _test_roundto;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);
    
    %local has_error __test_number;
    %let has_error=0;
    %let __test_number=123.4567894;

    data test_data;
        input n_digits expected;
        datalines;
1 123.5
2 123.46
3 123.457
4 123.4568
5 123.45679
6 123.456789
;
    run;

    data test_data;
        set test_data;
        length result diff 8.;
        result=roundto(&__test_number., n_digits);
    run;

    data test_data;
        set test_data;
        diff=result-expected;
    run;
    

    %test_suite(Testing roundto);
        %test_case(proc fcmp);
            data _null_;
                set test_data;
                call assertEqual(expected, result);
            run;

        %test_summary;

        %test_case(macro);
/* Note: test number is 123.4567894 to fully explore how 
         it handles rounding up/down                   */
            %let expecteds=123 123.5 123.46 123.457 123.4568 123.45679 123.456789;
            %do i=1 %to 7;
                %let expected=%scan(&expecteds., &i., %str( ));
                %let actual=%roundto(&__test_number., %eval(&i.-1));
                %assertEqual(&expected., &actual.);
            %end;

        %test_summary;

    %test_summary;

/*  Clean up test data */
    %if &has_error. ne 1 %then %do;
        proc delete data=test_data;
        run;
    %end;

    
%mend _test_roundto;

/* Macro to run round_to tests when __unit_tests is set */
%macro run_round_to_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %_test_roundto;
        %end;
    %end;
%mend run_round_to_tests;

%run_round_to_tests;
