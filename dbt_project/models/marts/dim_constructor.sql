-- One row per constructor across its whole history.
--
-- Built from race results rather than the constructors' championship, because
-- that title only began in 1958: every team that ever started a race appears
-- in results, but the 1950-57 teams never appear in standings at all.
--
-- Team colours come from the team_colours seed, which covers every team since
-- 1994. Earlier teams fall back to a neutral grey so Power BI always receives a
-- valid colour.

with entries as (

    select season, constructor_id, constructor_name, constructor_nationality
    from {{ ref('stg_jolpica__results') }}

),

colours as (

    select * from {{ ref('team_colours') }}

),

constructors as (

    select
        constructor_id,
        max_by(constructor_name, season)        as constructor_name,
        max_by(constructor_nationality, season) as constructor_nationality,
        min(season)                             as first_season,
        max(season)                             as last_season
    from entries
    group by constructor_id

)

select
    constructors.*,
    coalesce(colours.team_colour, '#9E9E9E') as team_colour,
    coalesce(colours.text_colour, '#000000') as text_colour
from constructors
left join colours
    on constructors.constructor_id = colours.constructor_id
