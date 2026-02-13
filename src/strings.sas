%macro __does_str_func_exist(func_name);
    %global func_exists;

    /* Define the functions in a function library, after checking that it doesn't already exist inside the sbfuncs.fn dataset */
    data check_lib;
        set sb_funcs.fns( keep=type subtype _key_ where=( type="Header" and
            subtype="Function" ) );

        drop type subtype;
    run;

    proc sql noprint;
        select _key_ into :func_exists separated by ' ' from check_lib where
            _key_="&func_name.";
    quit;

    %if %length(&func_exists) > 0 %then %do;
        %let func_exists=1;
        %return;
    %end;
    %else %do;
        %let func_exists=0;
    %end;

    &func_exists. 
%mend __does_str_func_exist;

%macro define_str_funcs;

    proc fcmp outlib=sb_funcs.fn.str;
        /* Function: str__split */
        /* Splits a string into an array of strings using a delimiter. */
        /*  */
        /* Parameters: */
        /* str - The string to split. */
        /* delimiter - The delimiter to split the string on. Default is a space. */
        /*  */
        /* Returns: */
        /* An array of strings. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy|is|a|cool|guy; */
        /* %let arr=str__split(&str, |); */
        /* %put &arr; */
        /*  */
        /* Output: */
        /* andy is a cool guy */
        function str__split(str $, delimiter $) $ ;
        length str $ 32767;
        length delimiter $ 32767;
        length result $ 32767;
        length i n;

        if missing(delimiter) then delimiter=' ';

        n=countw(str, delimiter);
        do i=1 to n;
            result=catx(' ', result, scan(str, i, delimiter));
        end;
        return (result);
        endsub;

        /* Function: index */
        /* Returns the position of a substring within a string. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /*  */
        /* Returns: */
        /* The position of the substring within the string, or -1 if the substring is not found. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let pos=index(&str, cool); */
        /* %put &pos; */
        /* Output: 11 */
        function str__index(str $, substr $) ;
        length str $ 32767;
        length substr $ 32767;
        length pos;
        pos=find(str, substr);
        return (pos);
        endsub;

        /* Function: str__replace */
        /* Replaces all occurrences of a substring within a string. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /* replacement - The string to replace the substring with. */
        /*  */
        /* Returns: */
        /* The modified string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let newstr=str__replace(&str, cool, awesome); */
        /* %put &newstr; */
        /* Output: andy is a awesome guy */
        function str__replace(str $, substr $, replacement $) $ 32767;
        length str $ 32767;
        length substr $ 32767;
        length replacement $ 32767;
        length newstr $ 32767;
        newstr=tranwrd(str, substr, replacement);
        return (newstr);
        endsub;

        /* Function: str__trim */
        /* Removes all leading and trailing spaces from a string. */
        /*  */
        /* Parameters: */
        /* str - The string to trim. */
        /*  */
        /* Returns: */
        /* The trimmed string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=   andy is a cool guy   ; */
        /* %let newstr=str__trim(&str); */
        /* %put &newstr; */
        /* Output: andy is a cool guy */
        function str__trim(str $) $ 32767;
        length str $ 32767;
        length newstr $ 32767;
        newstr=strip(str);
        return (newstr);
        endsub;

        /* Function: str__upper */
        /* Converts a string to uppercase. */
        /*  */
        /* Parameters: */
        /* str - The string to convert. */
        /*  */
        /* Returns: */
        /* The uppercase string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let newstr=str__upper(&str); */
        /* %put &newstr; */
        /* Output: ANDY IS A COOL GUY */
        function str__upper(str $) $ 32767;
        length str $ 32767;
        length newstr $ 32767;
        newstr=upcase(str);
        return (newstr);
        endsub;

        /* Function: str__lower */
        /* Converts a string to lowercase. */
        /*  */
        /* Parameters: */
        /* str - The string to convert. */
        /*  */
        /* Returns: */
        /* The lowercase string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=ANDY IS A COOL GUY; */
        /* %let newstr=str__lower(&str); */
        /* %put &newstr; */
        /* Output: andy is a cool guy */
        function str__lower(str $) $ 32767;
        length str $ 32767;
        length newstr $ 32767;
        newstr=lowcase(str);
        return (newstr);
        endsub;

        /* Function: str__length */
        /* Returns the length of a string. */
        /*  */
        /* Parameters: */
        /* str - The string to measure. */
        /*  */
        /* Returns: */
        /* The length of the string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let len=str__length(&str); */
        /* %put &len; */
        /* Output: 19 */
        function str__length(str $) ;
        length str $ 32767;
        length len;
        len=length(str);
        return (len);
        endsub;

        /* Function: str__contains */
        /* Checks if a string contains a substring. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /*  */
        /* Returns: */
        /* 1 if the substring is found, 0 otherwise. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let contains=str__contains(&str, cool); */
        /* %let notcontains=str__contains(&str, awesome); */
        /* %put &contains &notcontains; */
        /* Output: 1 0 */
        function str__contains(str $, substr $) ;
        length str $ 32767;
        length substr $ 32767;
        length contains;
        contains=index(str, substr) > 0;
        return (contains);
        endsub;

        /* Function: str__startswith */
        /* Checks if a string starts with a substring. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /*  */
        /* Returns: */
        /* 1 if the string starts with the substring, 0 otherwise. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let starts=str__startswith(&str, andy); */
        /* %let notstarts=str__startswith(&str, cool); */
        /* %put &starts &notstarts; */
        /* Output: 1 0 */
        function str__startswith(str $, substr $) ;
        length str $ 32767;
        length substr $ 32767;
        length starts;
        starts=substr(str, 1, length(substr))=substr;
        return (starts);
        endsub;

        /* Function: str__endswith */
        /* Checks if a string ends with a substring. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /*  */
        /* Returns: */
        /* 1 if the string ends with the substring, 0 otherwise. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let ends=str__endswith(&str, guy); */
        /* %let notends=str__endswith(&str, cool); */
        /* %put &ends &notends; */
        /* Output: 1 0 */
        function str__endswith(str $, substr $) ;
        length str $ 32767;
        length substr $ 32767;
        length ends;
        ends=substr(str, length(str) - length(substr) + 1)=substr;
        return (ends);
        endsub;

        /* Function: str__join */
        /* Joins an array of strings into a single string using a delimiter. */
        /*  */
        /* Parameters: */
        /* arr - The array of strings to join. */
        /* delimiter - The delimiter to join the strings with. Default is a space. */
        /*  */
        /* Returns: */
        /* The joined string. */
        /*  */
        /* Example: */
        /*  */
        /* %let arr=andy is a cool guy; */
        /* %let str=str__join(&arr, |); */
        /* %put &str; */
        /* Output: andy|is|a|cool|guy */
        function str__join(arr[*], delimiter $=' ') $ 32767;
        length delimiter $ 32767;
        length str $ 32767;
        length i n;
        n=dim(arr);
        do i=1 to n;
            str=catx(delimiter, str, arr[i]);
        end;
        return (str);
        endsub;

        /* Function: str__reverse */
        /* Reverses a string. */
        /*  */
        /* Parameters: */
        /* str - The string to reverse. */
        /*  */
        /* Returns: */
        /* The reversed string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let rev=str__reverse(&str); */
        /* %put &rev; */
        /* Output: yug looc a si ydna */
        function str__reverse(str $) $ 32767;
        length str $ 32767;
        length rev $ 32767;
        length i n;
        n=length(str);
        do i=n to 1 by -1;
            rev=cat(rev, substr(str, i, 1));
        end;
        return (rev);
        endsub;

        /* Function: str__find */
        /* Finds the first occurrence of a substring within a string. */
        /*  */
        /* Parameters: */
        /* str - The string to search. */
        /* substr - The substring to search for. */
        /*  */
        /* Returns: */
        /* The position of the substring within the string, or -1 if the substring is not found. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=andy is a cool guy; */
        /* %let pos=str__find(&str, cool); */
        /* %put &pos; */
        /* Output: 11 */
        function str__find(str $, substr $) ;
        length str $ 32767;
        length substr $ 32767;
        length pos;
        pos=index(str, substr);
        return (pos);
        endsub;

        /* Function: str__format */
        /* Formats a string using a format string. */
        /*  */
        /* Parameters: */
        /* str - The string to format, containing one or more placeholders. */
        /* args - The arguments to replace the placeholders with. */
        /*  */
        /* Returns: */
        /* The formatted string. */
        /*  */
        /* Example: */
        /*  */
        /* %let str=Hello, %s! Today is %s. It is %s degrees outside.; */
        /* %let formatted=str__format(&str, Andy, Monday, 75); */
        /* %put &formatted; */
        /* Output: Hello, Andy! Today is Monday. It is 75 degrees outside. */
        function str__format(str $, args[*]) $ 32767;
        length str $ 32767;
        length formatted $ 32767;
        length i n;
        n=dim(args);
        formatted=str;
        do i=1 to n;
            formatted=tranwrd(formatted, cats('%', put(i, 1.)), args[i]);
        end;
        return (formatted);
        endsub;
    run;


%mend define_str_funcs;

/*%define_str_funcs;*/
/**/
/*options cmplib=(sb_funcs.fn);*/

/* Returns the position of a substring within a string, or -1 if the substring is not found */
%macro str__index(
    str /* String to search */
    , substr /* Substring to search for */
);
    %let out=%sysfunc(find(&str, &substr));

    %if &out <= 0 %then %do;
        %let out=-1;
    %end;

    &out. 
%mend str__index;

/* Replaces all occurrences of a substring within a string */
%macro str__replace(
    str /* String to search */
    , substr /* Substring to search for */
    , replacement /* String to replace the substring with */
);
    %let out=%sysfunc(tranwrd(&str, &substr, &replacement));
    &out. 
%mend str__replace;

/* Removes all leading and trailing spaces from a string */
%macro str__trim(
    str /* String to trim */
);
    %let out=%sysfunc(strip(&str));
    &out. 
%mend str__trim;

%macro str__upper(
    str /* String to convert */
);
    %let out=%sysfunc(upcase(&str));
    &out. 
%mend str__upper;

/* Returns the lowercase version of a string */
%macro str__lower(
    str /* String to convert */
);
    %let out=%sysfunc(lowcase(&str));
    &out. 
%mend str__lower;

/* Returns the number of characters in a string */
%macro str__len( 
    str /* String to take the length of */ 
);
    %let out=%length(&str.);
    &out. 
%mend str__len;

/* Alias for str__len */
%macro str__length(     
    str /* String to take the length of */ 
);
    %let out=%str__len(&str.);
    &out. 
%mend str__length;

/* Returns 1 if a string contains a substring, 0 otherwise */
%macro str__contains(   
    str /* String to search */
    , substr /* Substring to search for */
);
    %if %str__index(&str., &substr.) > 0 %then %do;
        %let out=1;
    %end;
    %else %let out=0;
    &out. 
%mend str__contains;

/* Return the same string, split by a delimiter */
%macro str__split( 
    str /* String to split */
    , delim=' ' /* Delimiter to split the string on. Default is a space */
);
    %local i n out;
    %let n=%str__len(&str., &delim.);
    %do i=1 %to &n;
        %let out=%str__join(&out., %scan(&str., &i., &delim.));
    %end;

    &out. 
%mend str__split;

/* Returns a string sliced from the start to the end */
%macro str__slice( 
    str /* String to slice */
    , start /* Start index */
    , end /* End index */
);
    %if %length(&end.) = 0 %then %let end=%str__len(&str.);
    %if %length(&start.) = 0 %then %let start=1;
    
    %let n_chars=%eval(&end. - &start. + 1);
    %let out=%substr(&str., &start., &n_chars.);
    &out.
%mend str__slice;

/* Returns 1 if a string starts with a substring, 0 otherwise */
%macro str__startswith( 
    s /* String to check */
    , substr /* Substring to check for */ 
);

    %let slice=%str__slice(&s., 1, %str__len(&substr.));
    %if &slice. = &substr. %then %do;
        %let out=1;
    %end;
    %else %do;
        %let out=0;
    %end;
    &out. 
%mend str__startswith;

/* Returns 1 if a string ends with a substring, 0 otherwise */
%macro str__endswith( 
    str /* String to check */
    , substr /* Substring to check for */ 
);
    %let len=%str__len(&str.);
    %let substr_len=%str__len(&substr.);
    %let start_pos=%eval(&len. - &substr_len. + 1);
    %let slice=%str__slice(&str., &start_pos., &len.);
    %if &slice. = &substr. %then %do;
        %let out=1;
    %end;
    %else %do;
        %let out=0;
    %end;
    &out. 
%mend str__endswith;

/* Joins two strings into a single string, with a delimiter in between */
%macro str__join2( 
    s1 /* First string */
    , s2 /* Second string */
    ,delim /* Delimiter to join the strings with. Default is a space */ 
);
    %if %length(&delim.) = 0 %then %do;
        %let delim=%str( );
    %end;


    %let out=%sysfunc(catx(&delim, &s1, &s2));
    &out. 
%mend str__join2;

/* Reverses a string */
%macro str__reverse( 
    str /* String to reverse */
);
    %let len=%str__len(&str.);
    %let out=;
    %do i=&len. %to 1 %by -1;
        %let out=%sysfunc(cat(&out, %substr(&str., &i, 1)));
    %end;

    &out. 
%mend str__reverse;

/* Finds the first occurrence of a substring within a string */
%macro str__find( 
    str /* String to search */
    , substr /* Substring to search for */
);
    %let out=%str__index(&str., &substr.);
    &out. 
%mend str__find;

/* Formats a string using a format string, with placeholders given by ?s */
%macro str__format( 
    str /* String to format, containing one or more placeholders given by ?s */
    , args /* Arguments to replace the placeholders with, separated by spaces */ 
);

    %local i n out;
    %let n=%sysfunc(countw(&args.));
    %let out=&str.;
    %do i=1 %to &n;
        %let out=%sysfunc(tranwrd(&out., cats('?s', &i.), %scan(&args., &i.)));
    %end;

    &out. 
%mend str__format;

%macro test_strings;
    %sbmod(assert);

    %test_suite(Unit tests for string.sas);
        %let strIndex1=%str__index(andy is a cool guy, cool);
        %let strFind1=%str__find(andy is a cool guy, cool);
        %assertEqual(&strIndex1., 11); /* Test 1*/
        %assertEqual(&strFind1., 11); /* Test 2*/

        %let strIndex2=%str__index(andy is a cool guy, awesome);
        %let strFind2=%str__find(andy is a cool guy, awesome);
        %assertEqual(&strIndex2., -1); /* Test 3*/
        %assertEqual(&strFind2., -1); /* Test 4*/

        %let strReplace1=%str__replace(andy is a cool guy, cool, awesome);
        %assertEqual(&strReplace1., andy is a awesome guy); /* Test 5*/

        %let strReplaceNotFound=%str__replace(andy is a cool guy, awesome, cool);
        %assertEqual(&strReplaceNotFound., andy is a cool guy); /* Test 6*/

        %let strLen1=%str__len(andy);
        %let strLen1a=%str__length(andy);
        %assertEqual(&strLen1., 4); /* Test 7*/
        %assertEqual(&strLen1a., 4); /* Test 8*/

        %let strLen2=%str__len(andy weaver);
        %let strLen2a=%str__length(andy weaver);
        %assertEqual(&strLen2., 11); /* Test 9*/
        %assertEqual(&strLen2a., 11); /* Test 10*/

        %let strTrim1=%str__trim( andy is a cool guy );
        %assertEqual(&strTrim1., andy is a cool guy); /* Test 11*/

        %let strUpper1=%str__upper(andy is a cool guy);
        %assertEqual(&strUpper1., ANDY IS A COOL GUY); /* Test 12*/

        %let strLower1=%str__lower(ANDY IS A COOL GUY);
        %assertEqual(&strLower1., andy is a cool guy); /* Test 13*/

        %let strLower2=%str__lower(Andy is a Cool Guy);
        %assertEqual(&strLower2., andy is a cool guy); /* Test 14*/

        %let strContains1=%str__contains(andy is a cool guy, cool);
        %assertTrue(&strContains1., [andy is a cool guy] does actually contain [cool]); /* Test 15 */

        %let strContains2=%str__contains(andy is a cool guy, awesome);
        %assertFalse(&strContains2., [andy is a cool guy] does not contain [awesome]); /* Test 16 */

        %let strSlice1=%str__slice(andy is a cool guy, 1, 4);
        %assertEqual(&strSlice1., andy); /* Test 17 */

        %let strSlice2=%str__slice(andy is a cool guy, 6, 7);
        %assertEqual(&strSlice2., is); /* Test 18 */

        %let strSlice3=%str__slice(andy is a cool guy, 11, 14);
        %assertEqual(&strSlice3., cool); /* Test 19 */

        %let strSlice4=%str__slice(andy is a cool guy,, 4);
        %assertEqual(&strSlice4., andy); /* Test 20 */

        %let strSlice5=%str__slice(andy is a cool guy, 6,);
        %assertEqual(&strSlice5., is a cool guy); /* Test 21 */

        %assertTrue(
            %str__startswith(andy is a cool guy, andy), 
            [andy is a cool guy] does start with [andy]
        );  /* Test 22*/
        %assertFalse(
            %str__startswith(andy is a cool guy, cool), 
            [andy is a cool guy] does not start with [cool]
        ); /* Test 23*/

        %assertTrue(
            %str__endswith(andy is a cool guy, guy), 
            [andy is a cool guy] does end with [guy]
        ); /* Test 24 */
        %assertFalse(
            %str__endswith(andy is a cool guy, cool), 
            [andy is a cool guy] does not end with [cool]
        ); /* Test 25 */

        %let strJoin1=%str__join2(andy, is);
        %assertEqual(&strJoin1., andy is); /* Test 26 */

        %let strJoin2=%str__join2(andy, is, |);
        %assertEqual("&strJoin2.", "andy|is"); /* Test 27 */

    %test_summary;
%mend test_strings;

%test_strings;
