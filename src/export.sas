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
    %let filename=%_get_filename(&dataset., &out_lib.);
	proc export 
		replace
		data=&dataset.
		dbms=csv
		outfile="&filename.";
	run;

/*	%let cmd=chmod 777 &filename.;*/
/*	%shell(&cmd.);*/
	%shell( chmod 777 &filename. );

/*	%let cmd2=ls -lah &out_lib.;*/
/*	%shell(&cmd2.);*/
	%shell( ls -lah &out_lib. );
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

	%let ds=%sysfunc(lowcase(&dataset.));
	%let ds=%sysfunc(tranwrd(&dataset., '.', '__'));

	%let filename=&folder./&ds..csv;
	proc export 
		data=&dataset.
		replace 
		outfile="&filename."
		dbms=csv;
	run;
%mend export_csv_copy;

%macro test__export_to_csv;
	%sbmod(assert);

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

	%test_summary;

%mend test__export_to_csv;

%test__export_to_csv;
