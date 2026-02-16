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
