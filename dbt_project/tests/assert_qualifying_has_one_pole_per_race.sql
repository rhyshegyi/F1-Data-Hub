-- Every race with qualifying data (1994 onwards) has exactly one driver in
-- qualifying P1. The race list comes from staging, so a race the mart drops
-- fails here too.

with races as (

    select distinct {{ race_id('season', 'round') }} as race_id
    from {{ ref('stg_jolpica__qualifying') }}

),

poles as (

    select race_id, count(*) as pole_sitters
    from {{ ref('fct_qualifying') }}
    where qualifying_position = 1
    group by race_id

)

select races.race_id, poles.pole_sitters
from races
left join poles
    on races.race_id = poles.race_id
where coalesce(poles.pole_sitters, 0) <> 1
