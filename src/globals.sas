%macro init_global_var(variable);
	%if not %symexist(&variable.) %then %do;
		%global &variable.;
		%let &variable.=0;
	%end;
%mend init_global_var;

%macro init_global_vars;
	%let vars=imported__to_numb imported__logger imported__shell;
	
	%let N=%sysfunc(countw(&vars.));
	%do i=1 %to &N.;
		%let x=%sysfunc(scan(&vars., &i.));
		%init_global_var(&x.);
	%end;
%mend init_global_vars;

%macro test_globals;
	%if not %sysmacexist(assertTrue) %then %sbmod(assert);

	%test_suite(Testing globals.sas);
		%test_case(init_global_var sets to 0);
			%symdel __tmpvar / nowarn;
			%init_global_var(__tmpvar);
			%assertEqual(&__tmpvar., 0);
		%test_summary;

		%test_case(init_global_vars creates known flags);
			%init_global_vars;
			%assertTrue(%symexist(imported__to_numb), imported__to_numb exists);
			%assertTrue(%symexist(imported__logger), imported__logger exists);
			%assertTrue(%symexist(imported__shell), imported__shell exists);
		%test_summary;
	%test_summary;
%mend test_globals;

%macro run_global_tests;
%if %symexist(__unit_tests) %then %do;
  %if %superq(__unit_tests)=1 %then %do;
    %test_globals;
  %end;
%end;
%mend run_global_tests;

%run_global_tests;