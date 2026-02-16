options
  mprint
  mlogic
  symbolgen
  mprintnest
  mlogicnest
  source2
  mcompilenote=all
  msglevel=i
  notes
  source
  serror
  merror
  quotelenmax
;


%let val_year=2025;
%let val_month=12;
%let val_day=31;

/* Define folders and import sbmod + testing tools */
%let egdir=/sas/data/project/EG;
%let egsb=&egdir./ActShared/SmallBusiness;

/* Define model-specific directories */
%let tier_root=&egsb./Modeling/tier_models/bop/gen_1_2__2026;
%let codelib=&tier_root./code;


%let basesverse=/parm_share/small_business/modeling/sassyverse;

%include "&basesverse./sassyverse.sas";
%sv_init(
  base_path=&basesverse./src,
  include_pipr=1,
  include_tests=1
);

/* Load helper macros */
%sbmod(helpers, base_path=&codelib., reload=1);

%pipe(
  decfile.policy_lookup
  | select(sb_policy_key)
  | collect_to(policy_keys)
);