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
