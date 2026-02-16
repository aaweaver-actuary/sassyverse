%if not %sysmacexist(_abort) %then %include 'util.sas';
%if not %sysmacexist(_assert_ds_exists) %then %include 'validation.sas';

%include 'predicates.sas';

%include '_selectors/lambda.sas';
%include '_selectors/utils.sas';
%include '_selectors/starts_with.sas';
%include '_selectors/ends_with.sas';
%include '_selectors/contains.sas';
%include '_selectors/matches.sas';
%include '_selectors/cols_where.sas';

%include '_verbs/arrange.sas';
%include '_verbs/drop.sas';
%include '_verbs/filter.sas';
%include '_verbs/join.sas';
%include '_verbs/keep.sas';
%include '_verbs/mutate.sas';
%include '_verbs/collect_to.sas';
%include '_verbs/rename.sas';
%include '_verbs/select.sas';
%include '_verbs/summarise.sas';
