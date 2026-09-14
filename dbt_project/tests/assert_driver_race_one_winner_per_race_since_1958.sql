-- Every race has a winner, and from 1958, when shared drives stopped producing
-- shared wins, exactly one. The three earlier shared wins (1951, 1956, 1957)
-- are credited to both drivers, as the official records do. The race list
-- comes from results, not from the model, so a race the model drops fails.

with races as (

    select distinct season, round
    from {{ ref('int_results_joined_to_qualifying') }}

),

winners as (

    select season, round, sum(case when won then 1 else 0 end) as winners
    from {{ ref('int_driver_race') }}
    group by season, round

)

select races.season, races.round, winners.winners
from races
left join winners
    on races.season = winners.season
   and races.round = winners.round
where coalesce(winners.winners, 0) = 0
   or (races.season >= 1958 and winners.winners <> 1)
