/* MODULE DOC
File: src/shell.sas

1) Purpose in overall project
- General-purpose core utility module used by sassyverse contributors and downstream workflows.

2) High-level approach
- Defines reusable macro helpers and their tests, with small wrappers around common SAS patterns.

3) Code organization and why this scheme was chosen
- Public macros are grouped by theme, followed by focused unit tests and guarded autorun hooks.
- Code is organized as helper macros first, public API second, and tests/autorun guards last to reduce contributor onboarding time and import risk.

4) Detailed pseudocode algorithm
- Define utility macros and any private helper macros they require.
- Where needed, lazily import dependencies (for example assert/logging helpers).
- Expose a small public API with deterministic text/data-step output.
- Include test macros that exercise nominal and edge cases.
- Run tests only when __unit_tests is enabled to avoid production noise.

5) Acknowledged implementation deficits
- Macro-language utilities have limited static guarantees and rely on disciplined caller inputs.
- Some historical APIs prioritize backward compatibility over perfect consistency.
- Contributor docs are still text comments; there is no generated API reference yet.

6) Macros defined in this file
- _is_windows
- _shell_build_cmd
- shell
- shmkdir
- shpwd
- shrm
- shrm_dir
- shchmod
- shls
- test_shell
- run_shell_tests

7) Expected side effects from running/include
- Defines 11 macro(s) in the session macro catalog.
- Executes top-level macro call(s) on include: run_shell_tests.
- Contains guarded test autorun hooks; tests execute only when __unit_tests indicates test mode.
*/
%macro _is_windows;
    %local os;
    %let os=%upcase(&SYSSCP);
    %sysfunc(indexw(WIN WINDOWS WIN64, &os))
%mend _is_windows;

%macro _shell_build_cmd(cmd=, out_cmd=);
    %if %_is_windows %then %let &out_cmd=cmd /c %superq(cmd);
    %else %let &out_cmd=%superq(cmd);
%mend _shell_build_cmd;

%macro shell( cmd /*Command to pass to the shell.*/ );
    %local _cmd;
    %_shell_build_cmd(cmd=%superq(cmd), out_cmd=_cmd);

    options nosource nonotes errors=0;
    filename command pipe %sysfunc(quote(%superq(_cmd)));
    options source notes errors=20;

    data work._null_;
        infile command;
        input;
        put _infile_;
    run;

%mend shell;

%macro shmkdir(dir);
    %if %_is_windows %then %shell(mkdir "&dir.");
    %else %shell(mkdir -p &dir.);
%mend shmkdir;

%macro shpwd(dir=NONE);
    %if %_is_windows %then %do;
        %if "&dir."="NONE" %then %shell(cd);
        %else %shell(cd /d "&dir." ^& cd);
    %end;
    %else %do;
        %if "&dir."="NONE" %then %shell(pwd -P);
        %else %shell(pwd -P &dir.);
    %end;
%mend shpwd;

%macro shrm(file);
    %if %_is_windows %then %shell(del /q "&file.");
    %else %shell(rm &file.);
%mend shrm;

%macro shrm_dir(dir);
    %if %_is_windows %then %shell(rmdir /s /q "&dir.");
    %else %shell(rm -rf &dir.);
%mend shrm_dir;

%macro shchmod(x, to=777);
    %if %_is_windows %then %do;
        %put WARNING: shchmod is not supported on Windows. Skipping chmod on &x.;
    %end;
    %else %shell(chmod &to. &x.);
%mend shchmod;

%macro shls(dir=NONE, show_hidden=1);
    %if %_is_windows %then %do;
        %if "&dir."="NONE" %then %shell(dir /a);
        %else %shell(dir /a "&dir.");
    %end;
    %else %do;
        %if &show_hidden=1 %then %let opts=lah;
        %else %let opts=lh;

        %if "&dir."="NONE" %then %do;
            %shell(ls -&opts.);
        %end;
        %else %do;
            %shell(ls -&opts. &dir.);
        %end;
    %end;
%mend shls;

%macro test_shell;
    %if not %sysmacexist(assertTrue) %then %sbmod(assert);

    %test_suite(Testing shell.sas);
        %test_case(shell command builder respects host platform);
            %_shell_build_cmd(cmd=%str(echo hello), out_cmd=_sh_cmd);
            %if %_is_windows %then %do;
                %assertTrue(%eval(%index(%upcase(%superq(_sh_cmd)), CMD /C ECHO HELLO)=1), windows shell uses cmd /c prefix);
            %end;
            %else %do;
                %assertEqual(%superq(_sh_cmd), %str(echo hello));
            %end;
        %test_summary;
    %test_summary;
%mend test_shell;

%macro run_shell_tests;
    %if %symexist(__unit_tests) %then %do;
        %if %superq(__unit_tests)=1 %then %do;
            %test_shell;
        %end;
    %end;
%mend run_shell_tests;

%run_shell_tests;
