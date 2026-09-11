-- fct_points_by_round and fct_driver_standings reach a driver's season points
-- by different routes: one collapses shared drives to one row per driver per
-- race first, the other sums every car row directly. They must agree for every
-- season, including the 1950s, where collapsing shared drives is exactly the
-- step that could lose or double-count points.

with by_round as (

    select
        cast(floor(race_id / 100) as int) as season,
        driver_id,
        sum(total_points)                 as points_by_round
    from {{ ref('fct_points_by_round') }}
    group by 1, 2

)

select
    standings.season,
    standings.driver_id,
    standings.points_scored,
    by_round.points_by_round
from {{ ref('fct_driver_standings') }} as standings
left join by_round
    on standings.season = by_round.season
   and standings.driver_id = by_round.driver_id
where abs(coalesce(by_round.points_by_round, 0) - standings.points_scored) > 0.001
