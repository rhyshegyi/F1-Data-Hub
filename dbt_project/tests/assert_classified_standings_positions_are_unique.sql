-- Within a season, no two entrants may hold the same championship position.
--
-- This is the invariant the (wrongly) removed not_null test was reaching for.
-- Unclassified entrants -- '-' for scoring no points, 'D'/'E' for championship
-- disqualifications -- legitimately have no position at all, so they are
-- excluded rather than counted as ties.

with driver_positions as (

    select 'drivers' as championship, season, championship_position
    from {{ ref('stg_jolpica__driver_standings') }}
    where championship_position is not null

),

constructor_positions as (

    select 'constructors' as championship, season, championship_position
    from {{ ref('stg_jolpica__constructor_standings') }}
    where championship_position is not null

),

combined as (

    select * from driver_positions
    union all
    select * from constructor_positions

)

select championship, season, championship_position, count(*) as entrants
from combined
group by championship, season, championship_position
having count(*) > 1
