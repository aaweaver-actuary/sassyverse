%macro shell( cmd /*Command to pass to the shell.*/ );
    options nosource nonotes errors=0;
    filename command pipe "&cmd. ";
    options source notes errors=20;

    data work._null_;
        infile command;
        input;
        put _infile_;
    run;

%mend shell;

%macro shmkdir(dir);
    %shell(mkdir -p &dir.);
%mend shmkdir;

%macro shpwd(dir=NONE);
    %if "&dir."="NONE" %then %shell(pwd -P);
    %else %shell(pwd -P &dir.);
%mend shpwd;

%macro shrm(file);
    %shell(rm &file.);
%mend shrm;

%macro shrm_dir(dir);
    %shell(rm -rf &dir.);
%mend shrm_dir;

%macro shchmod(x, to=777);
    %shell(chmod &to. &x.);
%mend shchmod;

%macro shls(dir=NONE, show_hidden=1);
    %if &show_hidden=1 %then %let opts=lah;
    %else %let opts=lh;

    %if "&dir."="NONE" %then %do;
        %shell(ls -&opts.);
    %end;
    %else %do;
        %shell(ls -&opts. &dir.);
    %end;
%mend shls;

%shls;
