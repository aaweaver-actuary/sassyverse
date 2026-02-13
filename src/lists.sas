%macro foreach(list, codeblock);
    %local i item count;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %unquote(%superq(codeblock))
    %end;
%mend foreach;

%macro transform(list, surrounded_by=, delimited_by=);
    %local i item count transformedList;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %let transformedList = &transformedList &surrounded_by&item&surrounded_by;
        %if &i < &count %then %let transformedList = &transformedList &delimited_by;
    %end;

    &transformedList.
%mend transform;

%macro len(list, delimiters=);
    %local count;
    %if %length(%superq(delimiters)) = 0 %then 
        %let count = %sysfunc(countw(&list));
    %else
        %let count = %sysfunc(countw(&list, &delimiters));
    &count.
%mend len;

%macro nth(list, n);
    %local item;
    %let item = %scan(&list, &n);
    &item.
%mend nth;

%macro first(list);
    %local item;
    %let item = %nth(&list, 1);
    &item.
%mend first;

%macro last(list);
    %local count item;
    %let count = %len(&list);
    %let item = %nth(&list, &count);
    &item.
%mend last;

%macro unique(list);
    %local i item count uniqueList;
    %let count = %len(&list);

    %do i = 1 %to &count;
        %let item = %nth(&list, &i);
        %if not %index(&uniqueList, &item) %then %do;
            %let uniqueList = &uniqueList &item;
        %end;
    %end;

    &uniqueList.
%mend unique;

%macro sorted(list);
    %local i j count tmp;
    %let count = %len(&list);

    %if &count = 0 %then %do;
        
    %end;
    %else %do;
        %do i=1 %to &count;
            %let item&i=%scan(&list, &i, %str( ));
        %end;

        %do i=1 %to %eval(&count-1);
            %do j=%eval(&i+1) %to &count;
                %if %sysevalf(&&item&i > &&item&j) %then %do;
                    %let tmp=&&item&i;
                    %let item&i=&&item&j;
                    %let item&j=&tmp;
                %end;
            %end;
        %end;

        %local out;
        %let out=;
        %do i=1 %to &count;
            %let out=&out &&item&i;
        %end;
        %sysfunc(compbl(&out))
    %end;
%mend sorted;

%macro push(list, item);
    &list &item
%mend push;

%macro pop(list);
    %local count;
    %let count = %len(&list);
    %let list = %substr(&list, 1, %eval(%length(&list) - %length(%nth(&list, &count)) - 1));
    &list
%mend pop;

%macro concat(list1, list2);
    &list1 &list2
%mend concat;

%macro list_err(type);
    %global has_err;
    %if &type.=len %then %put ERROR: The list is empty.;

    %let has_err = 1;
%mend list_err;

%macro test_lists;
    %sbmod(assert);

    %test_suite(Testing lists.sas);
        %test_case(list basics);
            %let list=a b c a;
            %assertEqual(%len(&list), 4);
            %assertEqual(%nth(&list, 2), b);
            %assertEqual(%first(&list), a);
            %assertEqual(%last(&list), a);
        %test_summary;

        %test_case(unique and concat);
            %let uniq=%unique(&list);
            %assertEqual(%len(&uniq), 3);
            %let combo=%concat(a b, c d);
            %assertEqual(&combo, a b c d);
        %test_summary;

        %test_case(sorted numeric list);
            %let nums=3 1 2;
            %let sorted=%sorted(&nums);
            %assertEqual(&sorted, 1 2 3);
        %test_summary;

        %test_case(transform and foreach);
            %let t=%transform(a b, surrounded_by=%str(%'), delimited_by=%str(,));
            %assertEqual(%sysfunc(compbl(&t)), 'a' , 'b');

            %let acc=;
            %foreach(a b c, %nrstr(%let acc=&acc &item;));
            %assertEqual(%sysfunc(compbl(&acc)), a b c);
        %test_summary;
    %test_summary;
%mend test_lists;

%test_lists;
