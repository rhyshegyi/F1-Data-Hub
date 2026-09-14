-- Every win, podium and points finish belongs to exactly one streak of its
-- type, so the lengths of a driver's streaks add up to their total. A dropped
-- or double-counted start fails here.

with starts as (

    select driver_id, 'win' as streak_type, sum(case when won then 1 else 0 end) as qualifying_starts
    from {{ ref('int_driver_race') }} group by driver_id
    union all
    select driver_id, 'podium', sum(case when podium then 1 else 0 end)
    from {{ ref('int_driver_race') }} group by driver_id
    union all
    select driver_id, 'points', sum(case when scored_points then 1 else 0 end)
    from {{ ref('int_driver_race') }} group by driver_id

),

streaks as (

    select driver_id, streak_type, sum(streak_length) as streak_starts
    from {{ ref('fct_driver_streaks') }}
    group by driver_id, streak_type

)

select starts.*, streaks.streak_starts
from starts
left join streaks
    on starts.driver_id = streaks.driver_id
   and starts.streak_type = streaks.streak_type
where coalesce(streaks.streak_starts, 0) <> starts.qualifying_starts
