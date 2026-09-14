-- A season has a champion only once its final race has been run, and then
-- exactly one. Treating the current leader as champion counted a title for a
-- driver leading the championship with rounds still to go.

with champions as (

    select season, sum(case when is_champion then 1 else 0 end) as champions
    from {{ ref('fct_driver_standings') }}
    group by season

)

select
    seasons.season,
    seasons.races_completed,
    seasons.races_scheduled,
    coalesce(champions.champions, 0) as champions
from {{ ref('dim_season') }} as seasons
left join champions
    on seasons.season = champions.season
where (seasons.races_completed < seasons.races_scheduled and coalesce(champions.champions, 0) > 0)
   or (seasons.races_completed = seasons.races_scheduled and coalesce(champions.champions, 0) <> 1)
