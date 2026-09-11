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
--
-- Points include sprints. Sprints award championship points from 2021, and
-- leaving them out made every career and rolling total fall short from then on
-- -- 71 driver-seasons disagreed with the published standings before this was
-- fixed.

with race_level as (

    select
        season,
        round,
        driver_id,

        sum(points)                       as race_points,
        min(finish_position)              as best_finish_position,
        max(was_classified)               as was_classified,
        min(grid_position)                as grid_position,
        -- One entry per car, so this counts shared drives without
        -- double-counting the race itself.
        count(*)                          as cars_driven

    from {{ ref('int_results_joined_to_qualifying') }}
    group by season, round, driver_id

),

sprint_level as (

    select season, round, driver_id, sum(points) as sprint_points
    from {{ ref('stg_jolpica__sprint_results') }}
    group by season, round, driver_id

),

races as (

    select season, round, race_date
    from {{ ref('stg_jolpica__races') }}

),

race_entries as (

    -- Full outer join: a driver who scored in a sprint but did not take the
    -- race start would otherwise lose those points entirely.
    select
        coalesce(race_level.season, sprint_level.season)       as season,
        coalesce(race_level.round, sprint_level.round)         as round,
        coalesce(race_level.driver_id, sprint_level.driver_id) as driver_id,
        races.race_date,

        coalesce(race_level.race_points, 0)                    as race_points,
        coalesce(sprint_level.sprint_points, 0)                as sprint_points,
        coalesce(race_level.race_points, 0)
            + coalesce(sprint_level.sprint_points, 0)          as points,

        race_level.best_finish_position,
        coalesce(race_level.was_classified, false)             as was_classified,
        race_level.grid_position,
        coalesce(race_level.cars_driven, 0)                    as cars_driven

    from race_level
    full outer join sprint_level
        on race_level.season = sprint_level.season
       and race_level.round = sprint_level.round
       and race_level.driver_id = sprint_level.driver_id
    left join races
        on coalesce(race_level.season, sprint_level.season) = races.season
       and coalesce(race_level.round, sprint_level.round) = races.round

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
    race_points,
    sprint_points,
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
