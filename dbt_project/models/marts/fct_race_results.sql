-- One row per driver per car per race, 1950 to present.
--
-- Keys and measures only. Names, circuits and dates live in the dimensions and
-- are reached through relationships in Power BI -- the star schema Microsoft
-- recommends for it, and the reason this replaced the earlier wide race_results
-- table. Race results only: sprints are separate sessions, and their points
-- are counted in fct_points_by_round.

with results as (

    select * from {{ ref('int_results_joined_to_qualifying') }}

)

select
    {{ race_id('season', 'round') }} as race_id,
    driver_id,
    constructor_id,
    car_number,

    qualifying_position,
    best_qualifying_seconds,

    grid_position,
    finish_position,
    finish_position_text,
    was_classified,
    status,
    laps_completed,
    points,
    race_time_millis,
    fastest_lap_seconds,

    positions_gained,
    grid_penalty_positions,

    -- Classification is checked explicitly: an unclassified driver still carries
    -- a numeric finishing order, and a race with fewer than three classified
    -- finishers must not hand a podium to someone who retired.
    was_classified and finish_position = 1  as is_win,
    was_classified and finish_position <= 3 as is_podium,
    points > 0                              as scored_points

from results
