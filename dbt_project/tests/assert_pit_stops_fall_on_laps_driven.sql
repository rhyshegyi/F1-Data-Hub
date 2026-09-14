-- A driver can only pit on a lap they actually drove. A stop on a later lap
-- than the driver's last recorded lap means the two endpoints disagree about
-- who was where. Races whose laps aren't loaded yet are left out.

with last_laps as (

    select race_id, driver_id, max(lap) as last_lap
    from {{ ref('fct_lap_positions') }}
    where lap >= 1
    group by race_id, driver_id

),

races_with_laps as (

    select distinct race_id from last_laps

)

select
    stops.race_id,
    stops.driver_id,
    stops.stop_number,
    stops.lap,
    last_laps.last_lap
from {{ ref('fct_pit_stops') }} as stops
left join last_laps
    on stops.race_id = last_laps.race_id
   and stops.driver_id = last_laps.driver_id
where stops.race_id in (select race_id from races_with_laps)
  and (last_laps.last_lap is null or stops.lap > last_laps.last_lap)
