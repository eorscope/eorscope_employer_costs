:- module(eorscope_employer_costs,
          [ countries/1,                % -Countries
            country/2,                  % +Iso, -Country
            regions/1,                  % -Regions
            countries_in_region/2,      % +Region, -Countries
            contributions/2,            % +Iso, -Lines
            assumptions/2               % +Iso, -Assumptions
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(error)).
:- use_module(library(readutil)).

/** <module> EOR Scope dataset of statutory employer costs (76 countries)

Read-only lookup of the EOR Scope open dataset (CC BY 4.0), embedded at
compile time from the CSV files in the pack's data/ directory. No
dependencies, no network calls.

The library returns the figures as exported and computes nothing. Employer
cost totals are the ones published in the dataset; the library does not
recompute them. For a cost at another salary, use the calculator at
https://eorscope.com/eor-cost-calculator/.

Records are dicts:

  - country{iso, name, region, currency, example_salary_usd, example_role,
    example_place, basic_share_of_gross, employer_cost_pct,
    employer_cost_pct_printed, total_declared_floor, total_declared_ceiling,
    employer_cost_usd_month, total_excludes, fx_local_per_usd, fx_date,
    last_reviewed}
  - contribution{iso, country, currency, line_type, line_id, line_name,
    rate, base, base_factor, base_floor_annual_local, base_cap_annual_local,
    flat_annual_local, min_gross_annual_local, max_gross_annual_local,
    extra_kind, extra_value, secondary_source, thirteenth_month,
    total_declared_floor, total_declared_ceiling, in_total, applies, notes,
    source_name, source_url, source_checked_at}
  - assumption{iso, id, label, value, notes}

Text is a string, integers and floats are numbers, booleans are the atoms
=true= and =false=, dates are date(Y,M,D) and an empty optional value is
the atom =null=.

A country with total_declared_floor =true= publishes an "at least" figure,
not a total. Under total_declared_ceiling the modelled contribution base is
the highest the law allows, and lines with in_total =false= come on top. A
contribution's rate applies to its base times base_factor (1 unless the law
builds the base from more than the salary, as Mexico's integrated base
does), before base_floor_annual_local and base_cap_annual_local.

Sources and method: https://eorscope.com/methodology/. The figures are a
cost comparison, not legal or tax advice.

@license Code MIT; embedded data (data/) CC BY 4.0, see data/LICENSE.
*/

%!  countries(-Countries:list(dict)) is det.
%
%   Every country, sorted by ISO code.

countries(Countries) :-
    findall(C, summary_row(_, C), Countries).

%!  country(+Iso, -Country:dict) is semidet.
%
%   The country with the ISO 3166-1 alpha-2 code Iso (atom or string,
%   case-insensitive). Fails for an unknown code.

country(Iso, Country) :-
    iso_key(Iso, Key),
    summary_row(Key, Country).

%!  regions(-Regions:list(string)) is det.
%
%   The distinct regions, sorted.

regions(Regions) :-
    findall(R, ( summary_row(_, C), get_dict(region, C, R) ), Rs),
    sort(Rs, Regions).

%!  countries_in_region(+Region, -Countries:list(dict)) is det.
%
%   The countries of Region (case-insensitive), sorted by ISO code.

countries_in_region(Region, Countries) :-
    must_be(text, Region),
    string_lower(Region, Key),
    findall(C, ( summary_row(_, C),
                 get_dict(region, C, R),
                 string_lower(R, Key)
               ), Countries).

%!  contributions(+Iso, -Lines:list(dict)) is det.
%
%   The contribution and statutory extra lines of a country, in dataset
%   order; empty for an unknown code.

contributions(Iso, Lines) :-
    iso_key(Iso, Key),
    findall(L, contribution_row(Key, L), Lines).

%!  assumptions(+Iso, -Assumptions:list(dict)) is det.
%
%   The declared assumptions of a country, in dataset order; empty for an
%   unknown code.

assumptions(Iso, Assumptions) :-
    iso_key(Iso, Key),
    findall(A, assumption_row(Key, A), Assumptions).

iso_key(Iso, Key) :-
    must_be(text, Iso),
    string_upper(Iso, Key).


                 /*******************************
                 *          PARSING             *
                 *******************************/

%!  parse_csv(+Text, +Name, -Records:list(list(string))) is det.
%
%   RFC 4180 reader: comma separator, double-quoted fields that may hold
%   commas, doubled quotes and line breaks, LF or CRLF records, optional
%   BOM. Blank lines are skipped; every record must have as many fields
%   as the first. Errors raise error(syntax_error(csv(Name, Message)), _).

parse_csv(Text, Name, Records) :-
    string_codes(Text, Cs0),
    (   Cs0 = [0xFEFF|Cs] -> true ; Cs = Cs0 ),
    csv_records(Cs, Name, Records),
    (   Records = [Head|Rows]
    ->  length(Head, N),
        forall(member(R, Rows),
               (   length(R, M),
                   M == N
               ->  true
               ;   length(R, M),
                   format(atom(Msg), 'expected ~d fields, got ~d', [N, M]),
                   csv_fail(Name, Msg)
               ))
    ;   csv_fail(Name, empty)
    ).

csv_records([], _, []) :- !.
csv_records(Cs, Name, Records) :-
    (   eol(Cs, Rest)                   % blank line
    ->  csv_records(Rest, Name, Records)
    ;   csv_record(Cs, Name, Fields, Rest),
        Records = [Fields|More],
        csv_records(Rest, Name, More)
    ).

eol([0'\r,0'\n|R], R) :- !.
eol([0'\n|R], R) :- !.
eol([0'\r|R], R).

csv_record(Cs, Name, [F|Fs], Rest) :-
    csv_field(Cs, Name, F, Cs1),
    (   Cs1 = [0',|Cs2]
    ->  csv_record(Cs2, Name, Fs, Rest)
    ;   Cs1 == []
    ->  Fs = [], Rest = []
    ;   eol(Cs1, Rest)
    ->  Fs = []
    ).

csv_field([0'"|Cs], Name, Field, Rest) :-
    !,
    quoted(Cs, Name, Codes, Rest),
    (   ( Rest == [] ; Rest = [C|_], memberchk(C, `,\r\n`) )
    ->  string_codes(Field, Codes)
    ;   csv_fail(Name, 'extraneous character after a closing quote')
    ).
csv_field(Cs, Name, Field, Rest) :-
    unquoted(Cs, Name, Codes, Rest),
    string_codes(Field, Codes).

quoted([], Name, _, _) :-
    csv_fail(Name, 'unterminated quoted field').
quoted([0'",0'"|Cs], Name, [0'"|T], Rest) :- !,
    quoted(Cs, Name, T, Rest).
quoted([0'"|Cs], _, [], Cs) :- !.
quoted([C|Cs], Name, [C|T], Rest) :-
    quoted(Cs, Name, T, Rest).

unquoted([], _, [], []).
unquoted([C|Cs], Name, Codes, Rest) :-
    (   memberchk(C, `,\r\n`)
    ->  Codes = [], Rest = [C|Cs]
    ;   C == 0'"
    ->  csv_fail(Name, 'bare quote in an unquoted field')
    ;   Codes = [C|T],
        unquoted(Cs, Name, T, Rest)
    ).

csv_fail(Name, Msg) :-
    throw(error(syntax_error(csv(Name, Msg)), _)).

%   Field conversion. Column types follow the dataset's datapackage.json.

field(Row, Col, Value) :-
    (   memberchk(Col-V0, Row)
    ->  Value = V0
    ;   throw(error(existence_error(csv_column, Col), _))
    ).

str(Row, Col, S) :- field(Row, Col, S).

int(Row, Col, I) :-
    field(Row, Col, S),
    (   number_string(I, S), integer(I) -> true ; bad(Col, integer, S) ).

num(Row, Col, F) :-
    opt(Row, Col, F),
    (   F == null -> bad(Col, number, "") ; true ).

opt(Row, Col, F) :-
    field(Row, Col, S),
    (   S == ""
    ->  F = null
    ;   catch(number_string(N, S), _, fail)
    ->  F is float(N)
    ;   bad(Col, number, S)
    ).

bool(Row, Col, B) :-
    field(Row, Col, S),
    (   memberchk(S, ["true", "TRUE", "True", "1"]) -> B = true
    ;   memberchk(S, ["false", "FALSE", "False", "0"]) -> B = false
    ;   bad(Col, boolean, S)
    ).

day(Row, Col, D) :-
    field(Row, Col, S),
    (   S == ""
    ->  D = null
    ;   split_string(S, "-", "", [Ys, Ms, Ds]),
        string_length(Ys, 4), string_length(Ms, 2), string_length(Ds, 2),
        number_string(Y, Ys), number_string(M, Ms), number_string(Day, Ds),
        integer(Y), integer(M), integer(Day),
        catch(date_time_stamp(date(Y, M, Day, 0, 0, 0, 0, -, -), Stamp), _, fail),
        stamp_date_time(Stamp, date(Y, M, Day, _, _, _, _, _, _), 0)
    ->  D = date(Y, M, Day)
    ;   bad(Col, date, S)
    ).

bad(Col, Type, S) :-
    throw(error(type_error(Type, Col=S), _)).

read_rows(File, Rows) :-
    prolog_load_context(directory, Dir),
    atomic_list_concat([Dir, '/../data/', File], Path),
    read_file_to_string(Path, Text, [encoding(utf8)]),
    parse_csv(Text, File, [Head|Recs]),
    findall(Row, ( member(Rec, Recs), pairs_keys_values(Row, Head, Rec) ), Rows).

summary(Row, C) :-
    str(Row, "iso", Iso),
    str(Row, "country", Name),
    str(Row, "region", Region),
    str(Row, "currency", Currency),
    int(Row, "example_salary_usd", Salary),
    str(Row, "example_role", Role),
    str(Row, "example_place", Place),
    opt(Row, "basic_share_of_gross", Basic),
    num(Row, "employer_cost_pct", Pct),
    num(Row, "employer_cost_pct_printed", Printed),
    bool(Row, "total_declared_floor", Floor),
    bool(Row, "total_declared_ceiling", Ceiling),
    num(Row, "employer_cost_usd_month", USDMonth),
    str(Row, "total_excludes", Excludes),
    num(Row, "fx_local_per_usd", FX),
    day(Row, "fx_date", FXDate),
    day(Row, "last_reviewed", Reviewed),
    C = country{iso:Iso, name:Name, region:Region, currency:Currency,
                example_salary_usd:Salary, example_role:Role,
                example_place:Place, basic_share_of_gross:Basic,
                employer_cost_pct:Pct, employer_cost_pct_printed:Printed,
                total_declared_floor:Floor, total_declared_ceiling:Ceiling,
                employer_cost_usd_month:USDMonth, total_excludes:Excludes,
                fx_local_per_usd:FX, fx_date:FXDate, last_reviewed:Reviewed}.

contribution(Row, L) :-
    str(Row, "iso", Iso),
    str(Row, "country", Country),
    str(Row, "currency", Currency),
    str(Row, "line_type", Type),
    str(Row, "line_id", ID),
    str(Row, "line_name", Name),
    opt(Row, "rate", Rate),
    str(Row, "base", Base),
    opt(Row, "base_factor", Factor),
    opt(Row, "base_floor_annual_local", Floor0),
    opt(Row, "base_cap_annual_local", Cap),
    opt(Row, "flat_annual_local", Flat),
    opt(Row, "min_gross_annual_local", MinGross),
    opt(Row, "max_gross_annual_local", MaxGross),
    str(Row, "extra_kind", Kind),
    opt(Row, "extra_value", Extra),
    bool(Row, "secondary_source", Secondary),
    bool(Row, "thirteenth_month", Thirteenth),
    bool(Row, "total_declared_floor", Floor),
    bool(Row, "total_declared_ceiling", Ceiling),
    bool(Row, "in_total", InTotal),
    str(Row, "applies", Applies),
    str(Row, "notes", Notes),
    str(Row, "source_name", SourceName),
    str(Row, "source_url", SourceURL),
    day(Row, "source_checked_at", Checked),
    L = contribution{iso:Iso, country:Country, currency:Currency,
                     line_type:Type, line_id:ID, line_name:Name, rate:Rate,
                     base:Base, base_factor:Factor,
                     base_floor_annual_local:Floor0,
                     base_cap_annual_local:Cap, flat_annual_local:Flat,
                     min_gross_annual_local:MinGross,
                     max_gross_annual_local:MaxGross, extra_kind:Kind,
                     extra_value:Extra, secondary_source:Secondary,
                     thirteenth_month:Thirteenth, total_declared_floor:Floor,
                     total_declared_ceiling:Ceiling, in_total:InTotal,
                     applies:Applies, notes:Notes, source_name:SourceName,
                     source_url:SourceURL, source_checked_at:Checked}.

assumption(Row, A) :-
    str(Row, "iso", Iso),
    str(Row, "id", ID),
    str(Row, "label", Label),
    num(Row, "value", Value),
    str(Row, "notes", Notes),
    A = assumption{iso:Iso, id:ID, label:Label, value:Value, notes:Notes}.

%   The data are read once, when this file is compiled, and become facts.

data_clauses(Clauses) :-
    read_rows('country_summary.csv', SRows),
    maplist(summary, SRows, Cs),
    map_list_to_pairs([C, K]>>get_dict(iso, C, K), Cs, Pairs0),
    keysort(Pairs0, Pairs),
    findall(summary_row(K, C), member(K-C, Pairs), S),
    read_rows('country_contributions.csv', CRows),
    findall(contribution_row(K, L),
            ( member(R, CRows), contribution(R, L), get_dict(iso, L, K) ), Ls),
    read_rows('country_assumptions.csv', ARows),
    findall(assumption_row(K, A),
            ( member(R, ARows), assumption(R, A), get_dict(iso, A, K) ), As),
    append([S, Ls, As], Clauses).

term_expansion(eorscope_data, Clauses) :-
    data_clauses(Clauses).

eorscope_data.
