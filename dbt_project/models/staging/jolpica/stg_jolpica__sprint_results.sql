-- One row per driver per sprint race. Sprints began in 2021.
--
-- These matter because they award championship points. Without them, points
-- scored across a season disagrees with the published standings for every
-- season from 2021 onwards -- 18 points in 2021, 216 by 2023.
--
-- Kept as its own model rather than unioned into stg_jolpica__results: a sprint
-- is a separate session with its own result, and merging the two would make
-- "how did this driver finish the race" ambiguous.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_sprint_results') }}

),

exploded as (

    select pages.season, race, result
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_sprint_schema() }}')
    ) exploded_races as race
    lateral view explode(race.SprintResults) exploded_results as result

)

select
    try_cast(season as int)            as season,
    try_cast(race.round as int)        as round,
    result.Driver.driverId            as driver_id,
    result.Constructor.constructorId  as constructor_id,
    result.Constructor.name           as constructor_name,

    try_cast(result.number as int)    as car_number,
    try_cast(result.grid as int)      as grid_position,
    try_cast(result.position as int)  as finish_position,
    result.positionText               as finish_position_text,
    try_cast(result.points as double) as points,
    try_cast(result.laps as int)      as laps_completed,
    result.status                     as status

from exploded
