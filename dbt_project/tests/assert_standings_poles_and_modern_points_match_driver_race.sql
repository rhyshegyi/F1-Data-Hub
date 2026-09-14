-- Season poles and modern points in fct_driver_standings must match
-- int_driver_race, the same definitions used for careers and streaks. Poles are
-- grid slot 1, so seasons before 1994, which have no qualifying data, still
-- have poles.

with by_race as (

    select
        season,
        driver_id,
        sum(case when pole then 1 else 0 end) as poles,
        sum(modern_points)                    as modern_points
    from {{ ref('int_driver_race') }}
    group by season, driver_id

)

select
    standings.season,
    standings.driver_id,
    standings.poles,
    by_race.poles as expected_poles,
    standings.modern_points,
    by_race.modern_points as expected_modern_points
from {{ ref('fct_driver_standings') }} as standings
left join by_race
    on standings.season = by_race.season
   and standings.driver_id = by_race.driver_id
where not (standings.poles <=> coalesce(by_race.poles, 0))
   or not (standings.modern_points <=> coalesce(by_race.modern_points, 0))
