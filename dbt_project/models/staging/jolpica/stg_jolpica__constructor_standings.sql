-- One row per constructor per season: the final constructors' championship
-- classification, as published.
--
-- Starts in 1958. The constructors' title did not exist for the first eight
-- seasons of the world championship, so 1950-1957 are absent here by fact
-- rather than by omission.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_constructor_standings') }}

),

exploded as (

    select pages.season, standings_list, standing
    from pages
    lateral view explode(
        from_json(payload:MRData.StandingsTable.StandingsLists,
                  '{{ jolpica_constructor_standings_schema() }}')
    ) exploded_lists as standings_list
    lateral view explode(standings_list.ConstructorStandings) exploded_standings as standing

)

select
    try_cast(season as int)               as season,
    try_cast(standings_list.round as int) as final_round,
    standing.Constructor.constructorId    as constructor_id,
    standing.Constructor.name             as constructor_name,
    standing.Constructor.nationality      as constructor_nationality,

    try_cast(standing.position as int)    as championship_position,
    standing.positionText                 as championship_position_text,
    try_cast(standing.points as double)   as championship_points,
    try_cast(standing.wins as int)        as wins

from exploded
