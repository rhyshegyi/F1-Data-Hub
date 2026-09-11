-- From 1991 every result counts toward the title, so a driver's points summed
-- across int_driver_form must equal their published championship points.
--
-- Guards against the sprint omission recurring in the intermediate layer:
-- career and rolling points built from race results alone fall short by every
-- sprint point from 2021 onwards.

with form_totals as (

    select season, driver_id, sum(points) as points_from_form
    from {{ ref('int_driver_form') }}
    group by season, driver_id

),

standings as (

    select season, driver_id, championship_points
    from {{ ref('stg_jolpica__driver_standings') }}
    where season >= 1991

)

select
    standings.season,
    standings.driver_id,
    standings.championship_points,
    form_totals.points_from_form
from standings
left join form_totals
    on standings.season = form_totals.season
   and standings.driver_id = form_totals.driver_id
where coalesce(form_totals.points_from_form, 0) <> standings.championship_points
