-- One row per driver per season: the final drivers' championship
-- classification, as published, not as recomputed.
--
-- This model exists because points scored and championship points are not the
-- same number. Between 1950 and 1990 only a driver's best N results counted
-- toward the title, so summing stg_jolpica__results gives the wrong champion --
-- Prost outscored Senna in 1988 (105 to 94) and Hill outscored Surtees in 1964
-- (41 to 40), yet Senna and Surtees took the titles. Reproducing forty years of
-- varying dropped-score regulations would be guesswork; the source already
-- carries the answer.
--
-- A driver who changed teams mid-season holds several constructors, so those
-- stay as an array rather than being exploded, which would break the grain.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_driver_standings') }}

),

exploded as (

    select pages.season, standings_list, standing
    from pages
    lateral view explode(
        from_json(payload:MRData.StandingsTable.StandingsLists,
                  '{{ jolpica_driver_standings_schema() }}')
    ) exploded_lists as standings_list
    lateral view explode(standings_list.DriverStandings) exploded_standings as standing

)

select
    try_cast(season as int)                  as season,
    try_cast(standings_list.round as int)    as final_round,
    standing.Driver.driverId                 as driver_id,

    try_cast(standing.position as int)       as championship_position,
    standing.positionText                    as championship_position_text,

    -- Championship points, which for 1950-1990 is not the sum of points scored.
    try_cast(standing.points as double)      as championship_points,
    try_cast(standing.wins as int)           as wins,

    transform(standing.Constructors, c -> c.constructorId) as constructor_ids,
    transform(standing.Constructors, c -> c.name)          as constructor_names

from exploded
