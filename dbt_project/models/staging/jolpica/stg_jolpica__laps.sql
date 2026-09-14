-- One row per driver per lap: position and lap time. Available from 1996.
--
-- A race's laps span about a dozen pages, and a single lap's timings can be
-- split across two of them. Exploding every page down to individual timings
-- puts each lap back together, whichever page each driver landed on.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_laps') }}

),

exploded as (

    select pages.season, race, lap, timing
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_laps_schema() }}')
    ) exploded_races as race
    lateral view explode(race.Laps) exploded_laps as lap
    lateral view explode(lap.Timings) exploded_timings as timing

)

select
    try_cast(season as int)          as season,
    try_cast(race.round as int)      as round,
    try_cast(lap.number as int)      as lap,
    timing.driverId                  as driver_id,
    try_cast(timing.position as int) as position,
    timing.time                      as lap_time,
    {{ parse_lap_time('timing.time') }} as lap_time_seconds

from exploded
