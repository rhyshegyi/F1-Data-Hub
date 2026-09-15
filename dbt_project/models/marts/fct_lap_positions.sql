-- One row per driver per lap, 1996 to present: the source for the position
-- chart on the Race Weekend page.
--
-- Lap 0 is the starting grid, taken from race results, so every line on the
-- chart starts where the driver lined up rather than at the end of lap 1.
-- Pit-lane starters have no grid slot and so no lap 0.
--
-- is_pit_lap marks the laps a driver pitted on, from 2011 when pit stop data
-- begins. Before that it is always false, because the source doesn't say.

with laps as (

    select * from {{ ref('stg_jolpica__laps') }}

),

pit_laps as (

    select distinct season, round, driver_id, lap
    from {{ ref('stg_jolpica__pit_stops') }}

),

races_with_laps as (

    select distinct season, round from laps

),

grid as (

    select
        results.season,
        results.round,
        results.driver_id,
        min(results.grid_position) as grid_position
    from {{ ref('int_results_joined_to_qualifying') }} as results
    inner join races_with_laps
        on results.season = races_with_laps.season
       and results.round = races_with_laps.round
    where results.grid_position > 0
    group by results.season, results.round, results.driver_id

)

select
    {{ race_id('laps.season', 'laps.round') }} as race_id,
    laps.driver_id,
    laps.lap,
    laps.position,
    laps.lap_time_seconds,
    pit_laps.driver_id is not null as is_pit_lap
from laps
left join pit_laps
    on laps.season = pit_laps.season
   and laps.round = pit_laps.round
   and laps.driver_id = pit_laps.driver_id
   and laps.lap = pit_laps.lap
-- 16 timings between 2008 and 2018 have a lap time but no position in the
-- source. Left out rather than guessed, so a chart line skips that lap instead
-- of plotting a position nobody recorded.
where laps.position is not null

union all

select
    {{ race_id('season', 'round') }} as race_id,
    driver_id,
    0              as lap,
    grid_position  as position,
    cast(null as double) as lap_time_seconds,
    false          as is_pit_lap
from grid
