-- One row per constructor across its whole history.
--
-- Built from race results rather than the constructors' championship, because
-- that title only began in 1958: every team that ever started a race appears
-- in results, but the 1950-57 teams never appear in standings at all.

with entries as (

    select season, constructor_id, constructor_name, constructor_nationality
    from {{ ref('stg_jolpica__results') }}

)

select
    constructor_id,
    max_by(constructor_name, season)        as constructor_name,
    max_by(constructor_nationality, season) as constructor_nationality,
    min(season)                             as first_season,
    max(season)                             as last_season

from entries
group by constructor_id
