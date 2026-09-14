-- Lap 0 is the starting grid, so each driver's line on the position chart
-- starts where they lined up. Every driver with a grid slot in a race that has
-- lap data needs a lap 0 row at that position. Pit-lane starters (grid 0) have
-- no slot, and no lap 0.
--
-- Races with lap data come from the raw table rather than the mart, so a mart
-- that drops a race entirely fails here too.

with races_with_laps as (

    select distinct {{ race_id('season', 'round') }} as race_id
    from {{ source('jolpica_raw', 'raw_jolpica_laps') }}

),

grid as (

    select race_id, driver_id, min(grid_position) as grid_position
    from {{ ref('fct_race_results') }}
    where grid_position > 0
      and race_id in (select race_id from races_with_laps)
    group by race_id, driver_id

),

lap_zero as (

    select race_id, driver_id, position
    from {{ ref('fct_lap_positions') }}
    where lap = 0

)

select grid.race_id, grid.driver_id, grid.grid_position, lap_zero.position
from grid
left join lap_zero
    on grid.race_id = lap_zero.race_id
   and grid.driver_id = lap_zero.driver_id
where not (lap_zero.position <=> grid.grid_position)
