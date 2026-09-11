-- From 1991 the championship counts every result, so the points a driver is
-- shown to have scored must equal the points they were awarded.
--
-- This test is the reason the sprint endpoint is ingested at all. Without
-- sprint points it fails for every season from 2021 -- 18 points adrift in
-- 2021, 216 by 2023 -- which is exactly how the omission was found.

select
    season,
    driver_id,
    championship_points,
    points_scored,
    points_dropped
from {{ ref('fct_driver_standings') }}
where season >= 1991
  and points_dropped <> 0
