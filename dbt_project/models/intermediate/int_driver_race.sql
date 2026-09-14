-- One row per driver per race start: the base for career totals, streaks and
-- age records.
--
-- Shared drives are collapsed to the driver's best result, so a 1950s driver
-- who took over a second car counts as one start, not two. Unlike
-- int_driver_form, sprint-only entries are not included: every row here is a
-- Grand Prix the driver actually took part in.
--
-- modern_points rescores the race with today's 25-18-15-12-10-8-6-4-2-1 system
-- for a classified top ten, with no sprint or fastest-lap points, so a win is
-- worth the same in 1952 as in 2024. It exists to compare eras; the real points
-- stay in points.
--
-- pole means the driver's car started from grid slot 1. Grid positions exist
-- for every race since 1950, qualifying only from 1994, so this is the pole
-- definition that works across history. It differs from the qualifying pole
-- when a grid penalty moved the fastest qualifier back. A shared car in nine
-- races between 1951 and 1956 credits pole to each driver who drove it, as the
-- source cannot say who started it.

with results as (

    select * from {{ ref('int_results_joined_to_qualifying') }}

),

drivers as (

    select season, driver_id, date_of_birth
    from {{ ref('stg_jolpica__drivers') }}

),

race_level as (

    select
        season,
        round,
        driver_id,
        race_date,

        count(*)                                                    as cars_driven,
        max(was_classified)                                         as was_classified,
        min(case when was_classified then finish_position end)      as best_finish_position,
        min(grid_position)                                          as best_grid_position,
        sum(points)                                                 as points

    from results
    group by season, round, driver_id, race_date

)

select
    race_level.season,
    race_level.round,
    {{ race_id('race_level.season', 'race_level.round') }} as race_id,
    race_level.race_date,
    race_level.driver_id,

    drivers.date_of_birth,
    datediff(race_level.race_date, drivers.date_of_birth) as age_days,

    race_level.cars_driven,
    race_level.was_classified,
    race_level.best_finish_position,
    race_level.best_grid_position,
    race_level.points,

    coalesce(race_level.best_finish_position = 1, false)  as won,
    coalesce(race_level.best_finish_position <= 3, false) as podium,
    coalesce(race_level.best_grid_position = 1, false)    as pole,
    race_level.points > 0                                 as scored_points,

    case race_level.best_finish_position
        when 1 then 25
        when 2 then 18
        when 3 then 15
        when 4 then 12
        when 5 then 10
        when 6 then 8
        when 7 then 6
        when 8 then 4
        when 9 then 2
        when 10 then 1
        else 0
    end as modern_points

from race_level
left join drivers
    on race_level.season = drivers.season
   and race_level.driver_id = drivers.driver_id
