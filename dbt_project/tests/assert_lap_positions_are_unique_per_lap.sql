-- On any lap, each running position belongs to one driver.

select race_id, lap, position, count(*) as drivers
from {{ ref('fct_lap_positions') }}
where lap >= 1
group by race_id, lap, position
having count(*) > 1
