-- Two Jolpica endpoints checked against each other. In every race with lap
-- data, each driver who completed laps must have lap positions up to exactly
-- the number of laps the results say they completed.
--
-- Races without lap data (before 1996, or not loaded yet) are left out, so
-- this holds while the backfill is still running.
--
-- Warns rather than fails: the source itself sometimes disagrees. At the 2026
-- British Grand Prix the results credit Sainz with 51 laps, but the lap data
-- has a 52nd, a 2:05 lap well off his pace, most likely a post-race
-- correction applied to one endpoint and not the other. A handful of these is
-- the source; hundreds would mean the model is wrong, and the count in every
-- build shows which.

{{ config(severity='warn') }}

with laps as (

    select race_id, driver_id, max(lap) as last_lap
    from {{ ref('fct_lap_positions') }}
    where lap >= 1
    group by race_id, driver_id

),

races_with_laps as (

    select distinct race_id from laps

),

results as (

    select race_id, driver_id, max(laps_completed) as laps_completed
    from {{ ref('fct_race_results') }}
    where race_id in (select race_id from races_with_laps)
    group by race_id, driver_id

),

source_races as (

    select distinct {{ race_id('season', 'round') }} as race_id
    from {{ source('jolpica_raw', 'raw_jolpica_laps') }}

)

select
    coalesce(results.race_id, source_races.race_id) as race_id,
    results.driver_id,
    results.laps_completed,
    laps.last_lap
from source_races
left join results
    on source_races.race_id = results.race_id
left join laps
    on results.race_id = laps.race_id
   and results.driver_id = laps.driver_id
where results.race_id is null
   or (results.laps_completed > 0 and not (laps.last_lap <=> results.laps_completed))
