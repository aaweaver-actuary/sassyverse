%global REGEX_SPECIAL_CHARS;
%let REGEX_SPECIAL_CHARS=\.^$|?*+()[]{}; /* Used for escaping special characters in regex patterns */

/* Safely loads a string input for use in another string-modifying function. */
proc fcmp outlib=work.funcs.str;
  function safe_text_input(raw_str $) $ 32767;
    length safe_str $32767;
    safe_str = strip(raw_str);
    return(safe_str);
  endsub;
run;

proc fcmp outlib=work.funcs.str;
  function safe_macro_input(str_var $) $ 32767;
    length raw $32767 safe_str $32767;
    raw = symget(str_var);
    safe_str = safe_text_input(raw);
    return(safe_str);
run;

proc fcmp outlib=work.funcs.str;
  function is_regex_special_char(ch $) $ 1;
    if indexc(symget('REGEX_SPECIAL_CHARS'), ch) > 0 then return(1);
    else return(0);
  endsub;
run;

proc fcmp outlib=work.funcs.str;
  function prepend_backslash(ch $) $ 2;
    return(cats('\', ch));
  endsub;
run;

proc fcmp outlib=work.funcs.str;
  function escape_regex_chars(text $) $ 32767;
    length esc $32767 ch $1;
    esc = '';
    do i = 1 to length(text);
      ch = substr(text, i, 1);
      if is_regex_special_char(ch) then 
        esc = cats(esc, prepend_backslash(ch));
      else esc = cats(esc, ch);
    end;
    return(esc);
  endsub;
run;

/*
Compiled function that iterates over each char in a string, and removes matching
opening/closing quotes if they exist. Singletons are returned as-is.

Parameters
----------
text
  The input text to process.

Returns
-------
character
  The processed text with matching quotes removed.

Usage Note
----------
This is a compiled function for use inside data steps or other macro code, not a standalone macro.
*/
proc fcmp outlib=work.funcs.str;
  function remove_matching_quotes(text $) $ 32767;
    length stripped $32767;
    length raw $32767 q $1;
    raw = strip(symget('_in'));
    if length(text) >= 2 then do;
      if (substr(text, 1, 1) = substr(text, length(text), 1)) and
         (substr(text, 1, 1) in ('"', "'")) then
        stripped = substr(text, 2, length(text)-2);
      else stripped = text;
    end;
    else stripped = text;
    return(stripped);
  endsub;
run;
