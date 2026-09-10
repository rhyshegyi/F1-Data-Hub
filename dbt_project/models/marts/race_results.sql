-- Wide, denormalized race results: the table the dashboard queries directly.
--
-- Materialized as a table rather than a view. The point of this layer is that
-- the BI tool never joins -- a dashboard change should never become a modelling
-- change -- and that guarantee is worth the storage.
--
-- One row per driver per car per race, 1950 to present.

with results as (

    select * from {{ ref('int_results_joined_to_qualifying') }}

),

drivers as (

    select season, driver_id, full_name, driver_code, nationality
    from {{ ref('stg_jolpica__drivers') }}

)

select
    -- Keys
    results.season,
    results.round,
    results.driver_id,
    results.car_number,

    -- Race
    results.race_name,
    results.race_date,
    results.race_start_utc,
    results.circuit_id,
    results.circuit_country,

    -- Driver and team
    drivers.full_name        as driver_name,
    drivers.driver_code,
    drivers.nationality      as driver_nationality,
    results.constructor_id,
    results.constructor_name,

    -- Qualifying
    results.qualifying_position,
    results.best_qualifying_seconds,

    -- Race outcome
    results.grid_position,
    results.finish_position,
    results.finish_position_text,
    results.was_classified,
    results.status,
    results.laps_completed,
    results.points,
    results.race_time_millis,
    results.fastest_lap_seconds,

    -- Deltas the dashboard charts directly
    results.positions_gained,
    results.grid_penalty_positions,

    -- Convenience flags, so the dashboard filters without expressions
    results.finish_position = 1                as is_win,
    results.finish_position <= 3               as is_podium,
    results.points > 0                         as scored_points

from results
left join drivers
    on results.season = drivers.season
   and results.driver_id = drivers.driver_id
