%macro make_simple_indices(
    ds /* The dataset to make the index on */
    , col /* A space-separated list of column names to make indices on */
    , lib /* Libref (optional). Defaults to WORK */
);
    %if %length(&lib.)=0 %then 
        %let library=work;
    %else %let library=&lib.;

    %if %length(&col.) = 1 %then %do;
        %make_simple_index(&ds., &col., &lib.);
    %end;
    %else %do;
        %do i=1 %to %sysfunc(countw(&col.));
            %let cur=%scan(&col., &i.);
            %make_simple_index(&ds., &cur., &lib.);
        %end;
    %end;    
%mend make_simple_indices;

%macro make_simple_index(ds, col, lib);
    %if %length(&lib.)=0 %then 
        %let library=work;
    %else %let library=&lib.;

    proc datasets 
        library=&library. 
        nodetails nolist nowarn;
        sysecho "Adding index on the column &col. in &library..&ds.";
        modify &ds.;
            index create &col.;
        run;
    quit;
%mend make_simple_index;

%macro make_comp_index(ds, col, lib);
    %if %length(&lib.)=0 %then 
        %let library=work;
    %else %let library=&lib.;

    %local compkey;
    %do i=1 %to %sysfunc(countw(&col.));
        %let cur=%scan(&col., &i.);
        %if &i.=1 %then 
            %let compkey=&cur.;
        %else
            %let compkey=&compkey.&cur.;
    %end;

    proc datasets 
        library=&library. 
        nodetails nolist nowarn;
        sysecho "Adding composite index keyed by &col. in &library..&ds.";
        modify &ds.;
            index create &compkey.=(&col.);
        run;
    quit;
%mend make_comp_index;

/* The following macros alias the macros from above. I made the
mistake of forgetting the actual name one too many times.    */

%macro create_simple_indices(
    ds /* The dataset to make the index on */
    , col /* A space-separated list of column names to make indices on */
    , lib /* Libref (optional). Defaults to WORK */
);
    %if %length(&lib.) > 0 %then %do;
        %make_simple_indices(&ds., &col., &lib.)
    %end;
    %else %do;
        %make_simple_indices(&ds., &col.)
    %end;
%mend create_simple_indices;

%macro create_simple_index(
          ds /* The dataset to make the index on */
        , col /* A single column name from the dataset */
        , lib /* Libref (optional). Defaults to WORK */
    );
    %if %length(&lib.) > 0 %then %do;
        %make_simple_index(&ds., &col., &lib.)
    %end;
    %else %do;
        %make_simple_index(&ds., &col.)
    %end;
%mend create_simple_index;
