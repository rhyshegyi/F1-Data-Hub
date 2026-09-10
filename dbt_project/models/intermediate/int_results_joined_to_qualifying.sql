-- Every race result with its race context and, where the source has it, the
-- driver's qualifying session attached.
--
-- Grain follows results: one row per driver per car per race. Qualifying has at
-- most one row per driver per race, so the join cannot fan out. Race-level
-- attributes come from stg_jolpica__races rather than from the results payload,
-- because a race can straddle two raw pages.
--
-- Qualifying is null for every season before 1994, which is most of the history
-- here. Anything built on the deltas below must expect that.

with results as (

    select * from {{ ref('stg_jolpica__results') }}

),

races as (

    select * from {{ ref('stg_jolpica__races') }}

),

qualifying as (

    select * from {{ ref('stg_jolpica__qualifying') }}

)

select
    results.season,
    results.round,
    results.driver_id,
    results.car_number,
    results.constructor_id,
    results.constructor_name,

    races.race_name,
    races.race_date,
    races.race_start_utc,
    races.circuit_id,
    races.circuit_country,

    results.grid_position,
    results.finish_position,
    results.finish_position_text,
    results.points,
    results.laps_completed,
    results.status,
    results.race_time_millis,
    results.fastest_lap_seconds,

    qualifying.qualifying_position,
    qualifying.q1_seconds,
    qualifying.q2_seconds,
    qualifying.q3_seconds,

    -- least() ignores nulls, so a driver knocked out in Q1 is measured on the
    -- one time they set rather than coming out null.
    least(qualifying.q1_seconds, qualifying.q2_seconds, qualifying.q3_seconds)
        as best_qualifying_seconds,

    -- Whether the driver was classified at all. A retirement still carries a
    -- numeric finish_position, so position alone cannot answer this.
    results.finish_position_text rlike '^[0-9]+$' as was_classified,

    -- Positions made up during the race. Positive means places gained.
    -- Null when either end is unknown, never zero.
    case
        when results.grid_position is null or results.finish_position is null then null
        -- A grid position of 0 is the source's marker for a pit lane start,
        -- which has no meaningful starting slot to count from.
        when results.grid_position = 0 then null
        when not (results.finish_position_text rlike '^[0-9]+$') then null
        else results.grid_position - results.finish_position
    end as positions_gained,

    -- Grid slots lost between qualifying and the start, i.e. penalties.
    case
        when qualifying.qualifying_position is null or results.grid_position is null then null
        when results.grid_position = 0 then null
        else results.grid_position - qualifying.qualifying_position
    end as grid_penalty_positions

from results
left join races
    on results.season = races.season
   and results.round = races.round
left join qualifying
    on results.season = qualifying.season
   and results.round = qualifying.round
   and results.driver_id = qualifying.driver_id
