-- One row per driver per qualifying session. Available from 1994 onwards only.
--
-- Q1/Q2/Q3 are null for drivers eliminated in an earlier segment, and all three
-- are null for the pre-2006 formats, where the source records a qualifying
-- position but no per-segment times.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_qualifying') }}

),

exploded as (

    select pages.season, race, qualifying
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_qualifying_schema() }}')
    ) exploded_races as race
    lateral view explode(race.QualifyingResults) exploded_qualifying as qualifying

)

select
    try_cast(season as int)                  as season,
    try_cast(race.round as int)              as round,
    qualifying.Driver.driverId           as driver_id,
    qualifying.Constructor.constructorId as constructor_id,
    qualifying.Constructor.name          as constructor_name,

    try_cast(qualifying.number as int)       as car_number,
    try_cast(qualifying.position as int)     as qualifying_position,

    qualifying.Q1                        as q1_time,
    {{ parse_lap_time('qualifying.Q1') }} as q1_seconds,
    qualifying.Q2                        as q2_time,
    {{ parse_lap_time('qualifying.Q2') }} as q2_seconds,
    qualifying.Q3                        as q3_time,
    {{ parse_lap_time('qualifying.Q3') }} as q3_seconds

from exploded
