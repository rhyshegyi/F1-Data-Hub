-- One row per race. The race calendar, its circuit, and the scheduled start of
-- every session on the weekend.
--
-- The raw table's own `season` column is the key, not the season nested in the
-- payload: `season` is what the page was requested and watermarked under, so it
-- is the value the load is actually keyed on.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_races') }}

),

exploded as (

    select pages.season, race
    from pages
    lateral view explode(
        from_json(payload:MRData.RaceTable.Races, '{{ jolpica_races_schema() }}')
    ) exploded_races as race

)

select
    try_cast(season as int)                        as season,
    try_cast(race.round as int)                    as round,
    race.raceName                              as race_name,
    try_cast(race.date as date)                    as race_date,

    -- Nullable throughout the early eras: races before roughly 1960 carry a
    -- date but no time, and practice sessions are not recorded at all.
    {{ jolpica_session_start('race.date', 'race.time') }} as race_start_utc,
    {{ jolpica_session_start('race.FirstPractice.date', 'race.FirstPractice.time') }} as fp1_start_utc,
    {{ jolpica_session_start('race.SecondPractice.date', 'race.SecondPractice.time') }} as fp2_start_utc,
    {{ jolpica_session_start('race.ThirdPractice.date', 'race.ThirdPractice.time') }} as fp3_start_utc,
    {{ jolpica_session_start('race.Qualifying.date', 'race.Qualifying.time') }} as qualifying_start_utc,
    {{ jolpica_session_start('race.Sprint.date', 'race.Sprint.time') }} as sprint_start_utc,
    {{ jolpica_session_start('race.SprintQualifying.date', 'race.SprintQualifying.time') }} as sprint_qualifying_start_utc,

    race.Circuit.circuitId                     as circuit_id,
    race.Circuit.circuitName                   as circuit_name,
    race.Circuit.Location.locality             as circuit_locality,
    race.Circuit.Location.country              as circuit_country,
    try_cast(race.Circuit.Location.lat as double)  as circuit_latitude,
    try_cast(race.Circuit.Location.long as double) as circuit_longitude,

    race.url                                   as wikipedia_url

from exploded
