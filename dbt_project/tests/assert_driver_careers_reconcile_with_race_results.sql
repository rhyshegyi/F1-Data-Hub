-- Career totals must agree with the facts they summarise, reached by a
-- different route: starts and wins counted as distinct races in
-- fct_race_results (which still holds one row per car), titles counted in
-- fct_driver_standings. Every driver with a race result must have a career.

with from_results as (

    select
        driver_id,
        count(distinct race_id)                              as starts,
        count(distinct case when is_win then race_id end)    as wins,
        count(distinct case when is_podium then race_id end) as podiums
    from {{ ref('fct_race_results') }}
    group by driver_id

),

from_standings as (

    select driver_id, sum(case when is_champion then 1 else 0 end) as titles
    from {{ ref('fct_driver_standings') }}
    group by driver_id

)

select
    from_results.driver_id,
    from_results.starts,  careers.starts  as career_starts,
    from_results.wins,    careers.wins    as career_wins,
    from_results.podiums, careers.podiums as career_podiums,
    coalesce(from_standings.titles, 0) as titles, careers.titles as career_titles
from from_results
left join from_standings
    on from_results.driver_id = from_standings.driver_id
left join {{ ref('fct_driver_careers') }} as careers
    on from_results.driver_id = careers.driver_id
where careers.driver_id is null
   or careers.starts <> from_results.starts
   or careers.wins <> from_results.wins
   or careers.podiums <> from_results.podiums
   or careers.titles <> coalesce(from_standings.titles, 0)
