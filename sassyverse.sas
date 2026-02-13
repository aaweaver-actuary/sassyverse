/* sassyverse.sas - Single entrypoint to load the full macro suite. */
%macro sassyverse_init(base_path=, include_pipr=1, include_tests=0);
  %local root lastchar;

  %if %length(%superq(base_path))=0 %then %do;
    %put ERROR: base_path= is required and should point to the sassyverse src folder.;
    %return;
  %end;

  %let root=%sysfunc(tranwrd(%superq(base_path), \, /));
  %let lastchar=%substr(&root, %length(&root), 1);
  %if "&lastchar" ne "/" %then %let root=&root./;

  %include "&root.sassymod.sas";
  %include "&root.globals.sas";
  %include "&root.assert.sas";
  %include "&root.strings.sas";
  %include "&root.lists.sas";
  %include "&root.dates.sas";
  %include "&root.is_equal.sas";
  %include "&root.n_rows.sas";
  %include "&root.round_to.sas";
  %include "&root.shell.sas";
  %include "&root.logging.sas";
  %include "&root.export.sas";
  %include "&root.hash.sas";
  %include "&root.index.sas";
  %include "&root.dryrun.sas";

  %if &include_pipr %then %do;
    %include "&root.pipr/util.sas";
    %include "&root.pipr/validation.sas";
    %include "&root.pipr/_verbs/utils.sas";
    %include "&root.pipr/_verbs/arrange.sas";
    %include "&root.pipr/_verbs/drop.sas";
    %include "&root.pipr/_verbs/filter.sas";
    %include "&root.pipr/_verbs/join.sas";
    %include "&root.pipr/_verbs/keep.sas";
    %include "&root.pipr/_verbs/mutate.sas";
    %include "&root.pipr/_verbs/rename.sas";
    %include "&root.pipr/_verbs/select.sas";
    %include "&root.pipr/_verbs/summarise.sas";
    %include "&root.pipr/pipr.sas";
  %end;

  %if &include_tests %then %do;
    %include "&root.testthat.sas";
  %end;
%mend sassyverse_init;

%macro sassyverse_load(base_path=, include_pipr=1, include_tests=0);
  %sassyverse_init(
    base_path=&base_path,
    include_pipr=&include_pipr,
    include_tests=&include_tests
  );
%mend sassyverse_load;
