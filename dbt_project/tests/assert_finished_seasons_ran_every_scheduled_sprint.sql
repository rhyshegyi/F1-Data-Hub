-- In a season that has finished, every scheduled sprint weekend must have a
-- sprint result, and every sprint result must sit on a scheduled sprint weekend.
--
-- This is the check that would have caught 2021 reading as having no sprint
-- weekends at all: the schedule gave those three sprints a date but no time,
-- staging only exposed the (correctly null) timestamp, and the sessions
-- disappeared. Finished seasons are the only ones where the two counts must
-- match -- mid-season, upcoming sprints are scheduled but not yet run.

select
    season,
    sprint_weekends_scheduled,
    sprints_completed
from {{ ref('dim_season') }}
where races_completed = races_scheduled
  and sprint_weekends_scheduled <> sprints_completed
