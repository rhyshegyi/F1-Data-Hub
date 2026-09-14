-- Every finished season has a champion and a runner-up, so it must have a
-- title margin, and the margin can't be negative. The current season is
-- excluded: until it ends there is no champion.

select season, races_completed, races_scheduled, title_margin
from {{ ref('dim_season') }}
where races_completed = races_scheduled
  and not is_current_season
  and (title_margin is null or title_margin < 0)
