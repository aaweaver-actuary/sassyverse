%macro _is_windows;
    %local os;
    %let os=%upcase(&SYSSCP);
    %sysfunc(indexw(WIN WINDOWS WIN64, &os))
%mend _is_windows;

%macro shell( cmd /*Command to pass to the shell.*/ );
    %local _cmd;
    %if %_is_windows %then %let _cmd=cmd /c &cmd;
    %else %let _cmd=&cmd;

    options nosource nonotes errors=0;
    filename command pipe "&_cmd. ";
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

