-- Rolling and career-to-date form for each driver at each race.
--
-- Grain is one row per driver per race, not per driver per car per race. Shared
-- drives are collapsed first: a driver who took over a second car in the 1950s
-- scored points once for that race, and counting the entries separately would
-- distort every rolling window that crosses it.
--
-- Windows are ordered by race date rather than by (season, round) so career
-- totals carry across season boundaries in the order the races actually
-- happened.

with race_entries as (

    select
        season,
        round,
        driver_id,
        race_date,

        sum(points)                       as points,
        min(finish_position)              as best_finish_position,
        max(was_classified)               as was_classified,
        min(grid_position)                as grid_position,
        -- One entry per car, so this counts shared drives without
        -- double-counting the race itself.
        count(*)                          as cars_driven

    from {{ ref('int_results_joined_to_qualifying') }}
    group by season, round, driver_id, race_date

),

with_form as (

    select
        *,

        -- Career to date, inclusive of this race.
        count(*) over (
            partition by driver_id order by race_date
        ) as career_races_to_date,

        sum(points) over (
            partition by driver_id order by race_date
        ) as career_points_to_date,

        sum(case when best_finish_position = 1 then 1 else 0 end) over (
            partition by driver_id order by race_date
        ) as career_wins_to_date,

        -- Recent form, inclusive of this race. Early in a career the window is
        -- simply shorter -- it is not padded, so the average stays honest.
        sum(points) over (
            partition by driver_id order by race_date
            rows between 4 preceding and current row
        ) as points_last_5_races,

        avg(case when was_classified then best_finish_position end) over (
            partition by driver_id order by race_date
            rows between 4 preceding and current row
        ) as avg_finish_last_5_races,

        -- Form carried into this race, excluding it. This is the one to use for
        -- anything predictive: including the current race leaks the result.
        sum(points) over (
            partition by driver_id order by race_date
            rows between 5 preceding and 1 preceding
        ) as points_in_previous_5_races

    from race_entries

)

select
    season,
    round,
    driver_id,
    race_date,
    points,
    best_finish_position,
    was_classified,
    grid_position,
    cars_driven,
    career_races_to_date,
    career_points_to_date,
    career_wins_to_date,
    points_last_5_races,
    round(avg_finish_last_5_races, 2) as avg_finish_last_5_races,
    points_in_previous_5_races
from with_form
