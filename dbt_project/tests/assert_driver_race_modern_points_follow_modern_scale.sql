-- Rescoring every race with today's 25-18-15-12-10-8-6-4-2-1 system must hand
-- out exactly that scale, once, to the classified top ten.
--
-- Checked from 1965: shared drives ended in 1964, and before that a shared car
-- credits its finishing position to more than one driver. When fewer than ten
-- cars were classified, only as many positions are paid out as there were
-- classified finishers. The race list comes from results, not from the model,
-- so a race the model drops fails here too.

with races as (

    select
        season,
        round,
        least(sum(case when was_classified then 1 else 0 end), 10) as positions_paid
    from {{ ref('int_results_joined_to_qualifying') }}
    where season >= 1965
    group by season, round

),

awarded as (

    select season, round, sum(modern_points) as modern_points_awarded
    from {{ ref('int_driver_race') }}
    where season >= 1965
    group by season, round

),

scale as (

    select position, points
    from values (1, 25), (2, 18), (3, 15), (4, 12), (5, 10),
                (6, 8), (7, 6), (8, 4), (9, 2), (10, 1) as scale(position, points)

),

expected as (

    select
        races.season,
        races.round,
        coalesce(sum(scale.points), 0) as modern_points_expected
    from races
    left join scale
        on scale.position <= races.positions_paid
    group by races.season, races.round

)

select
    expected.season,
    expected.round,
    expected.modern_points_expected,
    awarded.modern_points_awarded
from expected
left join awarded
    on expected.season = awarded.season
   and expected.round = awarded.round
where not (expected.modern_points_expected <=> awarded.modern_points_awarded)
