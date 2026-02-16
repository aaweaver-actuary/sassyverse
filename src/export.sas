%macro _get_dataset_name(dataset);
	%if %str__find(&dataset., . ) > -1 %then 
		%let ds=%scan(&dataset., 2, . );
	%else %let ds=&dataset.;
	&ds.
%mend _get_dataset_name;

%macro _get_filename(dataset, out_lib);
	%let ds=%_get_dataset_name(&dataset.);

	%if %length(&out_lib.) = 0 %then %do;
        %put ERROR: An `out_lib` parameter must be passed to `export_to_csv`.;
        %return;
	%end;
    %else %let filename=&out_lib./&ds..csv;

	&filename.
%mend _get_filename;

%macro export_to_csv(dataset, out_lib);
	%local is_win;
    %let filename=%_get_filename(&dataset., &out_lib.);
	proc export 
		replace
		data=&dataset.
		dbms=csv
		outfile="&filename.";
	run;

	%let is_win=%_is_windows;
	%if &is_win %then %do;
		%shell(dir /a "&out_lib.");
	%end;
	%else %do;
		%shell(chmod 777 &filename.);
		%shell(ls -lah &out_lib.);
	%end;
%mend export_to_csv;

%macro export_with_temp_file(dataset, temp_file, out_folder=/sas/data/project/EG/ActShared/SmallBusiness/Modeling/dat/raw_csv);
	data &temp_file.;
		set &dataset.;
	run;

	%export_csv_copy(&dataset., out_folder=&out_folder.);

	proc delete data=&temp_file.;
	run;

%mend export_with_temp_file;

%macro export_csv_copy(dataset, out_folder=NONE);
	%let _Default=/sas/data/project/EG/ActShared/SmallBusiness/Modeling/dat/raw_csv;

	%if "&out_folder."="NONE" %then 
		%let folder=&_Default.;
	%else
		%let folder=&out_folder.;

	%let ds=%sysfunc(lowcase(%superq(dataset)));
	%let ds=%sysfunc(tranwrd(&ds., %str(.), __));

	%let filename=&folder./&ds..csv;
	proc export 
		data=&dataset.
		replace 
		outfile="&filename."
		dbms=csv;
	run;
%mend export_csv_copy;

%macro test__export_to_csv;
	%if not %sysmacexist(assertTrue) %then %sbmod(assert);

	%local out_lib;
	%let out_lib=%sysfunc(tranwrd(%sysfunc(pathname(work)), \, /));

	%macro assertEqualsDataset(actual);
		%assertEqual(&actual., dataset);
	%mend assertEqualsDataset;

	%test_suite(Testing export_to_csv);

		%test_case(_get_dataset_name);
			
			%let name1=%_get_dataset_name(L.dataset);
			%assertEqualsDataset(&name1.);

			%let name2=%_get_dataset_name(libname.dataset);
			%assertEqualsDataset(&name2.);

			%let name3=%_get_dataset_name(dataset);
			%assertEqualsDataset(&name3.);

		%test_summary;

		%test_case(_get_filename);
			%let filename1=%_get_filename(dataset1, &out_lib.);
			%let expected=&out_lib./dataset1.csv;
			%assertEqual("&filename1.", "&expected.");

		%test_summary;

		%test_case(export_to_csv writes file);
			data work._exp;
				x=1; output;
			run;

			%export_to_csv(work._exp, &out_lib.);

			%let filename=%_get_filename(work._exp, &out_lib.);
			filename _exp "&filename.";
			%let _exists=%sysfunc(fexist(_exp));
			filename _exp clear;

			%assertEqual(&_exists., 1);
		%test_summary;

		%test_case(export_csv_copy writes file);
			%export_csv_copy(work._exp, out_folder=&out_lib.);

			%let filename2=&out_lib./work___exp.csv;
			filename _exp2 "&filename2.";
			%let _exists2=%sysfunc(fexist(_exp2));
			filename _exp2 clear;

			%assertEqual(&_exists2., 1);
		%test_summary;

		%test_case(export_with_temp_file writes file);
			%export_with_temp_file(work._exp, work._exp_tmp, out_folder=&out_lib.);

			%let filename3=&out_lib./work___exp.csv;
			filename _exp3 "&filename3.";
			%let _exists3=%sysfunc(fexist(_exp3));
			filename _exp3 clear;

			%assertEqual(&_exists3., 1);
		%test_summary;

	%test_summary;

	filename _exp "&out_lib./_exp.csv";
	data _null_; rc=fdelete('_exp'); run;
	filename _exp clear;

	filename _exp2 "&out_lib./work___exp.csv";
	data _null_; rc=fdelete('_exp2'); run;
	filename _exp2 clear;

	proc datasets lib=work nolist; delete _exp _exp_tmp; quit;

%mend test__export_to_csv;

%if %symexist(__unit_tests) %then %do;
  %if %superq(__unit_tests)=1 %then %do;
    %test__export_to_csv;
  %end;
%end;