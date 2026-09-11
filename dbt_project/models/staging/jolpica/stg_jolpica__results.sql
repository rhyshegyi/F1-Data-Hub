-- One row per driver per race.
--
-- Jolpica paginates over result rows, so a race can straddle two raw pages and
-- appear twice, with a partial `Results` array in each. Exploding still yields
-- each result exactly once, but it does mean race-level attributes must come
-- from stg_jolpica__races rather than from here.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_results') }}

),

exploded as (

    select pages.season, race, result
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_results_schema() }}')
    ) exploded_races as race
    lateral view explode(race.Results) exploded_results as result

)

select
    try_cast(season as int)                as season,
    try_cast(race.round as int)            as round,
    result.Driver.driverId             as driver_id,
    result.Constructor.constructorId   as constructor_id,
    result.Constructor.name            as constructor_name,
    result.Constructor.nationality     as constructor_nationality,

    -- try_cast, not cast, throughout this layer. Six rows between 1961 and 1963
    -- carry the literal string 'None' as a car number, and a hard cast makes
    -- the whole view unqueryable for one bad value in 26,000 -- failing before
    -- any test can report it. Casting softly turns that into a null, which the
    -- not_null tests then report as a counted failure. The raw layer still has
    -- the original either way.
    try_cast(result.number as int)         as car_number,
    try_cast(result.grid as int)           as grid_position,

    -- Both are kept deliberately. A retirement still carries a numeric
    -- finishing order in `position`, while `positionText` is where R, D, E, W
    -- and N live. Dropping either loses information the other cannot express.
    try_cast(result.position as int)       as finish_position,
    result.positionText                as finish_position_text,

    -- Double, not int: shortened races in the 1950s awarded half points, and
    -- shared drives split them further.
    try_cast(result.points as double)      as points,

    try_cast(result.laps as int)           as laps_completed,
    result.status                      as status,

    try_cast(result.Time.millis as bigint) as race_time_millis,
    result.Time.time                   as race_time,

    -- Absent before roughly 2004; null rather than zero throughout.
    try_cast(result.FastestLap.rank as int) as fastest_lap_rank,
    try_cast(result.FastestLap.lap as int)  as fastest_lap_number,
    result.FastestLap.Time.time         as fastest_lap_time,
    {{ parse_lap_time('result.FastestLap.Time.time') }} as fastest_lap_seconds,
    try_cast(result.FastestLap.AverageSpeed.speed as double) as fastest_lap_avg_speed,
    result.FastestLap.AverageSpeed.units as fastest_lap_avg_speed_units

from exploded
