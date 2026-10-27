:- module(test_eorscope_employer_costs, []).
:- use_module(library(plunit)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(readutil)).
:- use_module(library(sha)).
:- use_module('../prolog/eorscope_employer_costs').

% Run with: swipl -g run_tests -t halt test/test_eorscope_employer_costs.pl

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../data'], Data),
   asserta(data_dir(Data)).

data_file(Name, Path) :-
    data_dir(Dir),
    atomic_list_concat([Dir, '/', Name], Path).

raw(Name, Text) :-
    data_file(Name, Path),
    read_file_to_string(Path, Text, [encoding(utf8)]).

% Records in a CSV text counted independently of the parser: line breaks
% outside quotes, minus the header.
count_records(Text, N) :-
    string_codes(Text, Cs),
    foldl(count_lf, Cs, 0-false, N0-_),
    (   last(Cs, 0'\n) -> N1 = N0 ; N1 is N0 + 1 ),
    N is N1 - 1.

count_lf(0'", N-Q0, N-Q) :- !, ( Q0 == true -> Q = false ; Q = true ).
count_lf(0'\n, N0-false, N-false) :- !, N is N0 + 1.
count_lf(_, S, S).

iso_code(S, Len) :-
    string(S),
    string_length(S, Len),
    string_upper(S, S),
    string_codes(S, Cs),
    forall(member(C, Cs), code_type(C, upper)).

:- begin_tests(eorscope_data_files).

% The embedded files are the 2026-10-13 export, byte for byte.
test(sha256, [forall(member(File-Hex,
        [ 'country_summary.csv'-'83e1cec0a902ff629be224e22e0c4c11b90adc2f77aaa1e2b2914a79e6075254',
          'country_contributions.csv'-'5c55cd63e18a9b8e60813653b600cbe1f0e1bafb560482c949ea5c225900ec85',
          'country_assumptions.csv'-'c204bf448d5aecc99968a5e37f71473233cc179b10238d18537e46eb573fd50a',
          'LICENSE'-'105ff773cdd84d09900a475230ad58a7207718ac9d95b7ec09176a4cb044de01'
        ])), Got == Hex]) :-
    data_file(File, Path),
    read_file_to_codes(Path, Bytes, [type(binary)]),
    sha_hash(Bytes, Hash, [algorithm(sha256), encoding(octet)]),
    hash_atom(Hash, Got).

:- end_tests(eorscope_data_files).

:- begin_tests(eorscope_csv_parser).

% Quotes, commas, doubled quotes, line breaks, CRLF, BOM, blank lines.
test(vector) :-
    eorscope_employer_costs:parse_csv(
        "\uFEFFa,b,c\r\n\"x, y\",\"say \"\"hi\"\"\",\"l1\nl2\"\r\n\n,,\"\"\n1,2,3",
        t, R),
    assertion(R == [ ["a", "b", "c"],
                     ["x, y", "say \"hi\"", "l1\nl2"],
                     ["", "", ""],
                     ["1", "2", "3"] ]).
test(field_count, [error(syntax_error(csv(t, _)))]) :-
    eorscope_employer_costs:parse_csv("a,b\n1\n", t, _).
test(after_quote, [error(syntax_error(csv(t, _)))]) :-
    eorscope_employer_costs:parse_csv("a\n\"x\"y\n", t, _).
test(bare_quote, [error(syntax_error(csv(t, _)))]) :-
    eorscope_employer_costs:parse_csv("a\nx\"y\n", t, _).
test(unterminated, [error(syntax_error(csv(t, _)))]) :-
    eorscope_employer_costs:parse_csv("a\n\"open\n", t, _).

:- end_tests(eorscope_csv_parser).

:- begin_tests(eorscope_countries).

% 76 countries, valid codes, case-insensitive lookup.
test(countries) :-
    countries(Cs),
    length(Cs, N),
    assertion(N == 76),
    raw('country_summary.csv', Text),
    count_records(Text, N2),
    assertion(N2 == N),
    maplist([C, I]>>get_dict(iso, C, I), Cs, Isos),
    assertion(is_set(Isos)),
    assertion(msort(Isos, Isos)),
    forall(member(C, Cs), check_country(C)),
    assertion(\+ country(xx, _)),
    assertion((country(de, DE), get_dict(iso, DE, "DE"))),
    assertion((country("de", DE2), get_dict(iso, DE2, "DE"))).

check_country(C) :-
    _{iso:I, name:Name, region:Region, currency:Cur,
      example_salary_usd:Sal, fx_local_per_usd:FX, employer_cost_pct:Pct,
      employer_cost_usd_month:USD, last_reviewed:Rev, fx_date:FXD,
      basic_share_of_gross:Basic} :< C,
    assertion(iso_code(I, 2)),
    assertion((Name \== "", Region \== "", iso_code(Cur, 3))),
    assertion((integer(Sal), Sal > 0, FX > 0, Pct >= 0, USD >= 0)),
    assertion(Rev = date(_, _, _)),
    assertion((Cur == "USD" ; FXD = date(_, _, _))),
    (   Basic == null -> true ; assertion((Basic > 0, Basic =< 1)) ),
    assertion((country(I, C2), C2 == C)).

% Mexico as printed on eorscope.com.
test(mexico_printed) :-
    country("MX", MX),
    assertion(get_dict(employer_cost_pct_printed, MX, 30.9)).

% Every country equals its row of country_summary.csv, split here without
% the parser (the file has no quoted field).
test(summary_rows) :-
    raw('country_summary.csv', Text),
    assertion(\+ sub_string(Text, _, _, _, "\"")),
    split_string(Text, "\n", "\r", Lines0),
    exclude(==(""), Lines0, [HeadLine|Lines]),
    split_string(HeadLine, ",", "", Head),
    forall(member(Line, Lines), check_row(Head, Line)).

check_row(Head, Line) :-
    split_string(Line, ",", "", Fs),
    assertion(same_length(Fs, Head)),
    pairs_keys_values(V, Head, Fs),
    memberchk("iso"-Iso, V),
    country(Iso, C),
    forall(member(Col-Key, [ "country"-name, "region"-region,
                             "currency"-currency, "example_role"-example_role,
                             "example_place"-example_place,
                             "total_excludes"-total_excludes ]),
           ( memberchk(Col-S, V), get_dict(Key, C, S2),
             assertion(S2 == S) )),
    memberchk("example_salary_usd"-SalS, V),
    assertion((number_string(Sal, SalS), get_dict(example_salary_usd, C, Sal))),
    forall(member(Col-Key, [ "basic_share_of_gross"-basic_share_of_gross,
                             "employer_cost_pct"-employer_cost_pct,
                             "employer_cost_pct_printed"-employer_cost_pct_printed,
                             "employer_cost_usd_month"-employer_cost_usd_month,
                             "fx_local_per_usd"-fx_local_per_usd ]),
           ( memberchk(Col-S, V), get_dict(Key, C, X),
             assertion(same_number(S, X)) )),
    forall(member(Col-Key, [ "total_declared_floor"-total_declared_floor,
                             "total_declared_ceiling"-total_declared_ceiling ]),
           ( memberchk(Col-S, V), get_dict(Key, C, B),
             ( S == "true" -> B2 = true ; B2 = false ),
             assertion(B == B2) )),
    forall(member(Col-Key, [ "fx_date"-fx_date, "last_reviewed"-last_reviewed ]),
           ( memberchk(Col-S, V), get_dict(Key, C, D),
             assertion(same_day(S, D)) )).

same_number("", null) :- !.
same_number(S, X) :- number_string(N, S), X =:= N.

same_day("", null) :- !.
same_day(S, date(Y, M, D)) :-
    format(string(S2), "~d-~|~`0t~d~2+-~|~`0t~d~2+", [Y, M, D]),
    S2 == S.

% Floor countries: an "at least" figure, flagged on the country and its lines.
test(floor) :-
    country("AE", AE),
    assertion(get_dict(total_declared_floor, AE, true)),
    assertion(get_dict(total_declared_ceiling, AE, false)),
    contributions("AE", Ls),
    forall(member(L, Ls), assertion(get_dict(total_declared_floor, L, true))),
    country("DE", DE),
    assertion(get_dict(total_declared_floor, DE, false)),
    countries(Cs),
    include([C]>>get_dict(total_declared_floor, C, true), Cs, Floors),
    length(Floors, NF),
    assertion(NF == 13).

% Regions cover every country once.
test(regions) :-
    regions(Rs),
    foldl([R, N0, N]>>( countries_in_region(R, Cs),
                        assertion(Cs \== []),
                        forall(member(C, Cs), assertion(get_dict(region, C, R))),
                        length(Cs, K), N is N0 + K ), Rs, 0, Total),
    countries(All),
    length(All, Total),
    countries_in_region("europe", E1),
    countries_in_region('Europe', E2),
    assertion(E1 == E2).

:- end_tests(eorscope_countries).

:- begin_tests(eorscope_contributions).

% Contribution lines, base factors (Mexico's integrated base).
test(lines) :-
    countries(Cs),
    foldl(check_lines, Cs, 0-[], Total-Factors),
    assertion(Total == 544),
    raw('country_contributions.csv', Text),
    count_records(Text, N2),
    assertion(N2 == Total),
    msort(Factors, Sorted),
    clumped(Sorted, Counts),
    assertion(Counts == [1.009-7, 1.049315-9, 1.049867-1, 1.08-4]),
    contributions(xx, None),
    assertion(None == []),
    contributions(mx, Mx1),
    contributions('MX', Mx2),
    length(Mx1, N3), length(Mx2, N4),
    assertion((N3 == N4, N3 > 0)).

check_lines(C, T0-F0, T-F) :-
    get_dict(iso, C, Iso),
    contributions(Iso, Ls),
    assertion(Ls \== []),
    length(Ls, N),
    T is T0 + N,
    foldl(check_line(C), Ls, F0, F).

check_line(C, L, F0, F) :-
    _{iso:Iso, name:Name, currency:Cur, total_declared_floor:Fl,
      total_declared_ceiling:Ce} :< C,
    _{iso:LIso, country:LName, currency:LCur, total_declared_floor:LFl,
      total_declared_ceiling:LCe, line_type:Type, line_id:ID, base:Base,
      base_factor:Factor, extra_kind:Kind, extra_value:Extra, rate:Rate,
      source_url:URL, source_checked_at:Checked} :< L,
    assertion((LIso == Iso, LCur == Cur, LName == Name)),
    assertion((LFl == Fl, LCe == Ce)),
    (   Type == "contribution"
    ->  assertion((memberchk(Base, ["gross", "basic", "flat", "band"]), Kind == "")),
        assertion(( Base == "flat" -> Factor == null ; Factor \== null )),
        (   Factor \== null, Factor =\= 1
        ->  F = [Factor|F0]
        ;   F = F0
        )
    ;   Type == "statutory_extra"
    ->  assertion(memberchk(Kind, ["percent", "months", "days"])),
        assertion((Extra \== null, Rate == null, Factor == null)),
        F = F0
    ;   assertion(fail)
    ),
    assertion((ID \== "", URL \== "", Checked = date(_, _, _))).

:- end_tests(eorscope_contributions).

:- begin_tests(eorscope_assumptions).

test(assumptions) :-
    countries(Cs),
    foldl([C, N0, N]>>( get_dict(iso, C, Iso),
                        assumptions(Iso, As),
                        forall(member(A, As),
                               assertion(( get_dict(iso, A, Iso),
                                           get_dict(id, A, ID), ID \== "",
                                           get_dict(label, A, Lb), Lb \== "" ))),
                        length(As, K), N is N0 + K ), Cs, 0, Total),
    assertion(Total == 108),
    assumptions(xx, None),
    assertion(None == []).

:- end_tests(eorscope_assumptions).
