-- One row per driver per race: points from the race and its sprint combined,
-- with the driver's rolling and career form at that point.
--
-- This exists for the points-progression chart. A running sum over race
-- results alone finishes short of the real total from 2021, by every sprint
-- point. It also gives int_driver_form a consumer -- an intermediate model
-- nothing reads is dead weight.
--
-- The season running total is left to DAX on purpose: it is a few lines of
-- measure, and computing it here would bake one particular reading of "to date"
-- into the table.

with form as (

    select * from {{ ref('int_driver_form') }}

)

select
    {{ race_id('season', 'round') }} as race_id,
    driver_id,

    race_points,
    sprint_points,
    points                            as total_points,

    best_finish_position,
    was_classified,

    career_races_to_date,
    career_points_to_date,
    career_wins_to_date,

    points_last_5_races,
    avg_finish_last_5_races,
    points_in_previous_5_races

from form
