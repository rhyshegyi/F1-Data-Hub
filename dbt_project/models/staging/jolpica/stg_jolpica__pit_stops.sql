-- One row per pit stop. Available from 2011.
--
-- duration is the time in the pit lane as a string: usually bare seconds
-- ("25.208"), but a long stop, such as repairs or a red-flag stop, can run
-- past a minute ("1:02.345"). parse_lap_time reads both.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_pit_stops') }}

),

exploded as (

    select pages.season, race, stop
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_pit_stops_schema() }}')
    ) exploded_races as race
    lateral view explode(race.PitStops) exploded_stops as stop

)

select
    try_cast(season as int)      as season,
    try_cast(race.round as int)  as round,
    stop.driverId                as driver_id,
    try_cast(stop.stop as int)   as stop_number,
    try_cast(stop.lap as int)    as lap,
    stop.time                    as time_of_day,
    stop.duration                as duration,
    {{ parse_lap_time('stop.duration') }} as duration_seconds

from exploded
