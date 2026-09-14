-- Every team that ran two cars in a qualifying session must produce exactly two
-- teammate rows, and no team with any other number of cars may produce rows.
--
-- One-car entries (38 since 1994) have no teammate to compare against, so they
-- are left out rather than paired with nobody.

with two_car_teams as (

    select season, round, constructor_id
    from {{ ref('stg_jolpica__qualifying') }}
    group by season, round, constructor_id
    having count(*) = 2

),

paired as (

    select season, round, constructor_id, count(*) as rows_paired
    from {{ ref('int_teammate_qualifying') }}
    group by season, round, constructor_id

)

select
    coalesce(two_car_teams.season, paired.season)                 as season,
    coalesce(two_car_teams.round, paired.round)                   as round,
    coalesce(two_car_teams.constructor_id, paired.constructor_id) as constructor_id,
    paired.rows_paired
from two_car_teams
full outer join paired
    on two_car_teams.season = paired.season
   and two_car_teams.round = paired.round
   and two_car_teams.constructor_id = paired.constructor_id
where two_car_teams.season is null
   or coalesce(paired.rows_paired, 0) <> 2
