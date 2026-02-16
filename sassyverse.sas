/* sassyverse.sas - Single entrypoint to load the full macro suite. */
%macro _sassyverse_include(path=, out_status=);
  %local _qpath;
  %let &out_status=0;

  %if %length(%superq(path))=0 %then %do;
    %put ERROR: sassyverse include path is empty.;
    %return;
  %end;

  %if not %sysfunc(fileexist(%superq(path))) %then %do;
    %put ERROR: Missing required sassyverse file: %superq(path);
    %return;
  %end;

  %let _qpath=%sysfunc(quote(%superq(path)));
  %include &_qpath;

  %if &syserr > 6 %then %do;
    %put ERROR: Failed while including %superq(path). SYSERR=&syserr;
    %return;
  %end;

  %let &out_status=1;
%mend;

%macro _sassyverse_include_list(root=, files=, out_failed=);
  %local _n _i _file _path _ok;
  %let &out_failed=0;

  %let _n=%sysfunc(countw(%superq(files), |, m));
  %do _i=1 %to &_n;
    %let _file=%sysfunc(strip(%scan(%superq(files), &_i, |, m)));
    %if %length(%superq(_file)) > 0 %then %do;
      %let _path=%superq(root)%superq(_file);
      %_sassyverse_include(path=%superq(_path), out_status=_ok);
      %if &_ok = 0 %then %do;
        %let &out_failed=1;
        %return;
      %end;
    %end;
  %end;
%mend;

%macro sassyverse_init(base_path=, include_pipr=1, include_tests=0);
  %local root lastchar;
  %local _incl_pipr _incl_tests;
  %local _incl_pipr_is_on _incl_tests_is_on;
  %local _incl_pipr_is_off _incl_tests_is_off;
  %local _sv_failed;
  %global _sassyverse_base_path;

  %if %length(%superq(base_path))=0 %then %do;
    %put ERROR: base_path= is required and should point to the sassyverse src folder.;
    %return;
  %end;

  %let root=%sysfunc(tranwrd(%superq(base_path), \, /));
  %let lastchar=%substr(&root, %length(&root), 1);
  %if "&lastchar" ne "/" %then %let root=&root./;
  %let _sassyverse_base_path=%superq(root);

  %_sassyverse_include_list(
    root=%superq(root),
    files=%str(
      sassymod.sas
      | globals.sas
      | assert.sas
      | strings.sas
      | buffer.sas
      | lists.sas
      | dates.sas
      | is_equal.sas
      | n_rows.sas
      | round_to.sas
      | shell.sas
      | logging.sas
      | export.sas
      | hash.sas
      | index.sas
    ),
    out_failed=_sv_failed
  );
  %if &_sv_failed %then %return;

  %let _incl_pipr=%upcase(%superq(include_pipr));
  %let _incl_tests=%upcase(%superq(include_tests));
  %if "%superq(_incl_pipr)" = "" %then %let _incl_pipr=0;
  %if "%superq(_incl_tests)" = "" %then %let _incl_tests=0;

  %let _incl_pipr_is_on=%sysfunc(indexw(1 YES TRUE Y ON, %superq(_incl_pipr)));
  %let _incl_tests_is_on=%sysfunc(indexw(1 YES TRUE Y ON, %superq(_incl_tests)));
  %let _incl_pipr_is_off=%sysfunc(indexw(0 NO FALSE N OFF, %superq(_incl_pipr)));
  %let _incl_tests_is_off=%sysfunc(indexw(0 NO FALSE N OFF, %superq(_incl_tests)));

  %if (&_incl_pipr_is_on = 0) and (&_incl_pipr_is_off = 0) %then %do;
    %put WARNING: include_pipr=%superq(include_pipr) is not recognized. Defaulting to include_pipr=0.;
  %end;
  %if (&_incl_tests_is_on = 0) and (&_incl_tests_is_off = 0) %then %do;
    %put WARNING: include_tests=%superq(include_tests) is not recognized. Defaulting to include_tests=0.;
  %end;

  %if "%superq(_incl_pipr_is_on)" ne "0" %then %do;
    %_sassyverse_include_list(
      root=%superq(root),
      files=%str(
        pipr/util.sas
        | pipr/predicates.sas
        | pipr/validation.sas
        | pipr/_selectors/lambda.sas
        | pipr/_selectors/utils.sas
        | pipr/_selectors/starts_with.sas
        | pipr/_selectors/ends_with.sas
        | pipr/_selectors/contains.sas
        | pipr/_selectors/matches.sas
        | pipr/_selectors/cols_where.sas
        | pipr/_verbs/utils.sas
        | pipr/_verbs/arrange.sas
        | pipr/_verbs/drop.sas
        | pipr/_verbs/filter.sas
        | pipr/_verbs/join.sas
        | pipr/_verbs/keep.sas
        | pipr/_verbs/mutate.sas
        | pipr/_verbs/collect_to.sas
        | pipr/_verbs/rename.sas
        | pipr/_verbs/select.sas
        | pipr/_verbs/summarise.sas
        | pipr/pipr.sas
      ),
      out_failed=_sv_failed
    );
    %if &_sv_failed %then %return;
  %end;

  %if "%superq(_incl_tests_is_on)" ne "0" %then %do;
    %_sassyverse_include(path=%superq(root)testthat.sas, out_status=_sv_failed);
    %if &_sv_failed = 0 %then %return;
  %end;
%mend sassyverse_init;

%macro sassyverse_load(base_path=, include_pipr=1, include_tests=0);
  %sassyverse_init(
    base_path=&base_path,
    include_pipr=&include_pipr,
    include_tests=&include_tests
  );
%mend sassyverse_load;

%macro sv_init(base_path=, include_pipr=1, include_tests=0);
  %sassyverse_init(
    base_path=&base_path,
    include_pipr=&include_pipr,
    include_tests=&include_tests
  );
%mend sv_init;
