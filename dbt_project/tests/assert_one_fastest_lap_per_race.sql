-- Every race with fastest-lap data (2004 onwards) has exactly one fastest lap.
-- The race list comes from staging, so a mart that loses the flag fails here.

with races as (

    select distinct {{ race_id('season', 'round') }} as race_id
    from {{ ref('stg_jolpica__results') }}
    where fastest_lap_time is not null

),

fastest as (

    select race_id, count(*) as fastest_laps
    from {{ ref('fct_race_results') }}
    where is_fastest_lap
    group by race_id

)

select races.race_id, fastest.fastest_laps
from races
left join fastest
    on races.race_id = fastest.race_id
where coalesce(fastest.fastest_laps, 0) <> 1
