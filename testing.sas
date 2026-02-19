/* MODULE DOC
File: testing.sas

1) Purpose in overall project
- Top-level test harness entry file for local/integration workflows.

2) High-level approach
- Sets deterministic library paths, initializes framework, and runs targeted helper/test modules.

3) Code organization and why this scheme was chosen
- Configuration values are declared up front; execution calls are grouped at the bottom for quick editability.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Define base paths and helper library roots.
- Include the root framework entrypoint.
- Initialize framework with test flags suitable for local development.
- Import helper modules needed by the specific test workflow.
- Run selected test macros and inspect results in the SAS log.

5) Acknowledged implementation deficits
- Environment-specific paths require contributor adjustment outside the default setup.
- This file favors convenience over strict parameterization.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- (No %macro definitions in this file; file is include/run orchestration only.)

7) Expected side effects from running/include
- Executes top-level macro call(s) on include: sv_init, sbmod, pipe.
*/

%dbg(At the top of testing.sas);
/* Define folders and import sbmod + testing tools */
%let egdir=/sas/data/project/EG;
%let egsb=&egdir./ActShared/SmallBusiness;

/* Define model-specific directories */
%let tier_root=&egsb./Modeling/tier_models/bop/gen_1_2__2026;
%let codelib=&tier_root./code;


%let basesverse=/parm_share/small_business/modeling/sassyverse;

%dbg(%str(Defined base paths, now including sassyverse.sas));
%include "&basesverse./sassyverse.sas";

%dbg(Initializing sassyverse with:);
%dbg(%str(base_path=&basesverse./src));
%dbg(include_pipr=1);
%dbg(include_tests=1);
%sv_init(
  base_path=&basesverse./src,
  include_pipr=1,
  include_tests=1
);
%dbg(sassyverse initialized successfully, now loading helpers);

/* Load helper macros */
%sbmod(helpers, base_path=&codelib., reload=1);

%dbg(Helpers loaded, now smoke testing pipe macro);

%pipe(
  decfile.policy_lookup
  | select(sb_policy_key)
  | collect_to(policy_keys)
);

%dbg(Testing complete. Check SAS log for details and results.);