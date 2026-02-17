/* Truncate a macro variable name >32 characters down to 32 characters */
%macro truncate_varname(varname);
    %substr(&varname.1, 31)
%mend truncate_varname;

/* Convert a value to a boolean (0 or 1) */
%macro _sbmod_bool(value, default=0);
    %local _raw _up;
    %let _raw=%superq(value);
    %if %length(%superq(_raw))=0 %then &default;
    %else %do;
        %let _up=%upcase(%superq(_raw));
        %if %sysfunc(indexw(1 Y YES TRUE T ON, &_up)) > 0 %then 1;
        %else %if %sysfunc(indexw(0 N NO FALSE F OFF, &_up)) > 0 %then 0;
        %else &default;
    %end;
%mend _sbmod_bool;

/* Normalize path-like module names into safe macro-variable key text */
%macro _sbmod_safe_key(text=, out_key=_sbmod_safe_key);
    %local _in _out;
    %let _in=%superq(text);

    data _null_;
        length raw key ch $32767;
        raw = symget('_in');
        key = '';
        do i = 1 to length(raw);
            ch = substr(raw, i, 1);
            if prxmatch('/[A-Za-z0-9_]/', ch) > 0 then key = cats(key, ch);
            else key = cats(key, '_');
        end;
        if lengthn(key) = 0 then key = 'module';
        call symputx('_out', key, 'L');
    run;

    %let &out_key=%superq(_out);
%mend _sbmod_safe_key;

/* Set the shared log level in a way that works before/after logging.sas is loaded */
%macro _sbmod_set_log_level(level=INFO);
    %global log_level;
    %if %sysmacexist(set_log_level) %then %set_log_level(%superq(level));
    %else %let log_level=%upcase(%superq(level));
%mend _sbmod_set_log_level;

/* Enable DEBUG logs for a single sbmod call */
%macro _sbmod_use_dbg_begin(use_dbg=0);
    %if %_sbmod_bool(%superq(use_dbg), default=0) %then %do;
        %_sbmod_set_log_level(level=DEBUG);
    %end;
%mend _sbmod_use_dbg_begin;

/* Return logging to INFO at the end of a single sbmod call */
%macro _sbmod_use_dbg_end(use_dbg=0);
    %if %_sbmod_bool(%superq(use_dbg), default=0) %then %do;
        %_sbmod_set_log_level(level=INFO);
    %end;
%mend _sbmod_use_dbg_end;

%macro import_variable(varname);
/* Main include/import code path */
    %global &varname.;
    %if "%qsubstr(%superq(base_path), %length(%superq(base_path)), 1)" = "/" %then
        %let file=&base_path.&module..sas;
    %else
        %let file=&base_path/&module..sas;

    %if %sysfunc(fileexist(&file.)) %then %do;
        %include "&file.";
        %let &varname.=1;
        %put NOTE: Module &module. imported successfully.;
    %end;
    %else %do;
        %put ERROR: Module &module. not found at &file.;
    %end;
%mend import_variable;

%macro sbmod(
    module /* Module name to import */
    , base_path= /* Folder containing the module to import */
    , reload=NO /* Re-import if already loaded */
    , use_dbg=0 /* If 1/YES/TRUE, set log_level=DEBUG for this call only */
);
    %local varname _module_key;

    %_sbmod_safe_key(text=%superq(module), out_key=_module_key);
    %let varname=_imported__&_module_key.;
    %if %length(&varname.) >= 32 %then %let varname=%truncate_varname(&varname.);

    %if %length(%superq(base_path))=0 %then %do;
        %if %symexist(_sassyverse_base_path) %then %let base_path=%superq(_sassyverse_base_path);
        %else %let base_path=/sas/data/project/EG/aweaver/macros;
    %end;

    %_sbmod_use_dbg_begin(use_dbg=%superq(use_dbg));

    %if %symexist(&varname.) ne 1 %then %do;
        %import_variable(&varname.);
    %end;
    %else %do;
        %if (%symexist(&varname.)=1) and ("&reload." ne "NO") %then %do;
            %import_variable(&varname.);
        %end;
        %else %do;
            %put NOTE: Module &module. already imported.;
        %end;
    %end;

    %_sbmod_use_dbg_end(use_dbg=%superq(use_dbg));
%mend sbmod;

%macro sassymod(module, base_path=, reload=NO, use_dbg=0);
    %sbmod(module=&module., base_path=&base_path., reload=&reload., use_dbg=&use_dbg.);
%mend sassymod;

%macro test_sassymod;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing sassymod helpers);
        %test_case(truncate_varname caps length);
            %let longname=_imported__this_is_a_very_long_module_name;
            %let trunc=%truncate_varname(&longname.);
            %assertTrue(%eval(%length(&trunc.) <= 32), truncated length <= 32);
        %test_summary;

        %test_case(sbmod marker key sanitizes path-like module names);
            %_sbmod_safe_key(text=%str(pipr/predicates), out_key=_sm_key1);
            %_sbmod_safe_key(text=%str(module.with-dash), out_key=_sm_key2);
            %assertEqual(%superq(_sm_key1), pipr_predicates);
            %assertEqual(%superq(_sm_key2), module_with_dash);
        %test_summary;

        %test_case(use_dbg helper toggles debug then restores info);
            %_sbmod_set_log_level(level=INFO);
            %_sbmod_use_dbg_begin(use_dbg=1);
            %assertEqual(%upcase(%superq(log_level)), DEBUG);
            %_sbmod_use_dbg_end(use_dbg=1);
            %assertEqual(%upcase(%superq(log_level)), INFO);
        %test_summary;

        %test_case(use_dbg helper is no-op when disabled);
            %_sbmod_set_log_level(level=INFO);
            %_sbmod_use_dbg_begin(use_dbg=0);
            %assertEqual(%upcase(%superq(log_level)), INFO);
            %_sbmod_use_dbg_end(use_dbg=0);
            %assertEqual(%upcase(%superq(log_level)), INFO);
        %test_summary;
    %test_summary;
%mend test_sassymod;

%macro run_sassymod_tests;
    %if %symexist(__unit_tests) %then %do;
    %if %superq(__unit_tests)=1 %then %do;
        %test_sassymod;
    %end;
    %end;
%mend run_sassymod_tests;

%run_sassymod_tests;
