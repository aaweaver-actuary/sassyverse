%macro truncate_varname(varname);
/* Truncate a macro variable name >32 characters down to 
   32 characters */
    %substr(&varname.1, 31)
%mend truncate_varname;

%macro import_variable(varname);
/* This is the main import code block. It runs when all the applicable
   conditions pass. */
    %global &varname.;
    %let file=&base_path/&module..sas;

    %if %sysfunc(fileexist(&file.)) %then %do;
        %include "&file.";

        data _null_;
            call execute( '%let ' || "&varname." || ' = 1' );
        run;
        %put NOTE: Module &module. imported successfully.;
    %end;

    %else %do;
        %put ERROR: Module &module. not found at &file.;
    %end;
%mend import_variable;

%macro sbmod(
    module /* Module name to import */
    , base_path=/sas/data/project/EG/aweaver/macros /* Folder containing the module to import */
    , reload=NO /* If the module has already been defined in this session, should it be redefined? Generally no, but during macro development this could make sense. */);
	/*
		The `sbmod` macro is used to import a module into the global scope.			
		The module is only imported once, and subsequent calls to `sbmod` with the	
		same module name will not re-import the module. (This is the goal of the varname)
		variable. The module is assumed to be located in the directory				
		`/sas/data/project/EG/aweaver/macros/` and have the file extension `.sas`.	
																					
		Usage:																		
		%sbmod(module_name);														
		Includes the module `module_name` into the global scope, assuming you are	
		using Andy's macro repository.												
																					
		%sbmod(module_name, base_path=/path/to/modules);							
		Includes the module `module_name` into the global scope, where the module	
		is located at `/path/to/modules/module_name.sas`.							
	*/
    %let varname=_imported__&module.;
	%if %length(&varname.) >= 32 %then
		%let varname=%truncate_varname(&varname.);

    %if %symexist(&varname.) ne 1 %then %do;
        %import_variable(&varname.);
    %end;
    %else %do;
        %if (%symexist(&varname.)=1)
            and ("&reload." ne "NO") %then %do;
            %import_variable(&varname.);
        %end;
        %else %do;
            %put NOTE: Module &module. already imported.;
        %end;
    %end;
%mend sbmod;

%macro sassymod(module, base_path=/sas/data/project/EG/aweaver/macros, reload=NO);
    %sbmod(&module., &base_path., &reload.);
%mend sassymod;

%macro test_sassymod;
    %sbmod(assert);

    %test_suite(Testing sassymod helpers);
        %test_case(truncate_varname caps length);
            %let longname=_imported__this_is_a_very_long_module_name;
            %let trunc=%truncate_varname(&longname.);
            %assertTrue(%eval(%length(&trunc.) <= 32), truncated length <= 32);
        %test_summary;
    %test_summary;
%mend test_sassymod;

%test_sassymod;