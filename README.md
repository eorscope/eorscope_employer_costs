# eorscope_employer_costs

SWI-Prolog pack that embeds the EOR Scope dataset of statutory employer
costs, as read-only dict records. No dependencies, no network calls.

- 76 countries: employer cost in % and USD per month at an example salary,
  local currency, exchange rate and review date
- 544 employer contribution and statutory extra lines, each with rate, base,
  base factor, floor/ceiling, source URL and date
- 108 declared assumptions (the case each country's total holds for)

Source of the data: the EOR Scope open dataset, https://eorscope.com/data/
(CC BY 4.0), export of 2026-10-13.

## Install

    swipl pack install https://github.com/eorscope/employer-costs-prolog.git

## Usage

    :- use_module(library(eorscope_employer_costs)).

    ?- country(de, DE), get_dict(employer_cost_pct_printed, DE, Pct).
    ?- contributions("DE", Lines).        % [] for an unknown code
    ?- countries_in_region("Europe", Cs).
    ?- regions(Rs).
    ?- assumptions(mx, As).
    ?- countries(All).                    % sorted by ISO code

country/2 fails for an unknown code. Codes and regions are case-insensitive
and may be atoms or strings.

Records are dicts tagged country, contribution and assumption. Text is a
string, booleans are the atoms true and false, dates are date(Y,M,D) and an
empty optional value is the atom null. Field names follow the CSV columns
(country/2 renames the column "country" to name).

The pack is a lookup library: it returns the figures as exported and
computes nothing. Countries flagged total_declared_floor publish an "at
least" figure, not a total: read their employer_cost_pct as "at least".
Under total_declared_ceiling the modelled contribution base is the highest
the law allows and lines with in_total false come on top. A contribution's
rate applies to its base times base_factor (1 unless the law builds the
base from more than the salary, as Mexico's integrated base does).

For a cost at another salary, use the EOR cost calculator,
https://eorscope.com/eor-cost-calculator/, which runs the full computation.
How each figure is sourced and checked is set out in the methodology,
https://eorscope.com/methodology/. Every country has its own employer of
record page, https://eorscope.com/employer-of-record/, with the contribution
lines and their official sources.

Cost comparison, not legal or tax advice.

## Tests

    swipl --on-error=status -g run_tests -t halt test/test_eorscope_employer_costs.pl

The tests check the sha256 of the embedded files, the CSV reader, and the
same counts and invariants as the other EOR Scope packages (76 countries,
544 lines, 108 assumptions, 13 floor countries). Tested with SWI-Prolog
10.0.2.

## Updating the data

Copy country_summary.csv, country_contributions.csv, country_assumptions.csv
and LICENSE of a dataset export (https://eorscope.com/data/) into data/,
update the sha256 values in the test, then run the tests. The files are
read when the library is compiled. data/ is marked -text in .gitattributes
so that Git keeps the files byte for byte.

## Licence

Code: MIT, see LICENSE.

Data (data/): CC BY 4.0, see data/LICENSE. Attribution: EOR Scope,
published by Tresor Kaya EI (Les Creavores), France,
https://eorscope.com/methodology/.
