-- A streak runs over consecutive starts by the same driver, not consecutive
-- calendar races: a race the driver missed doesn't break it. Each streak must
-- be exact (its length is the number of starts between its first and last
-- race, and every one of them qualifies) and maximal (the driver's start just
-- before and just after it does not qualify).

with starts as (

    select
        driver_id,
        race_id,
        won,
        podium,
        scored_points,
        row_number() over (partition by driver_id order by race_date, race_id) as start_number
    from {{ ref('int_driver_race') }}

),

bounds as (

    select
        streaks.driver_id,
        streaks.streak_type,
        streaks.first_race_id,
        streaks.streak_length,
        first_start.start_number as first_number,
        last_start.start_number  as last_number
    from {{ ref('fct_driver_streaks') }} as streaks
    left join starts as first_start
        on streaks.driver_id = first_start.driver_id
       and streaks.first_race_id = first_start.race_id
    left join starts as last_start
        on streaks.driver_id = last_start.driver_id
       and streaks.last_race_id = last_start.race_id

),

inside as (

    select
        bounds.driver_id,
        bounds.streak_type,
        bounds.first_race_id,
        sum(case bounds.streak_type
                when 'win' then cast(starts.won as int)
                when 'podium' then cast(starts.podium as int)
                when 'points' then cast(starts.scored_points as int)
            end) as qualifying_inside
    from bounds
    inner join starts
        on bounds.driver_id = starts.driver_id
       and starts.start_number between bounds.first_number and bounds.last_number
    group by bounds.driver_id, bounds.streak_type, bounds.first_race_id

),

neighbours as (

    select
        bounds.driver_id,
        bounds.streak_type,
        bounds.first_race_id,
        max(case bounds.streak_type
                when 'win' then starts.won
                when 'podium' then starts.podium
                when 'points' then starts.scored_points
            end) as neighbour_qualifies
    from bounds
    inner join starts
        on bounds.driver_id = starts.driver_id
       and (starts.start_number = bounds.first_number - 1
            or starts.start_number = bounds.last_number + 1)
    group by bounds.driver_id, bounds.streak_type, bounds.first_race_id

)

select
    bounds.*,
    bounds.last_number - bounds.first_number + 1 as starts_spanned,
    inside.qualifying_inside,
    neighbours.neighbour_qualifies
from bounds
left join inside
    on bounds.driver_id = inside.driver_id
   and bounds.streak_type = inside.streak_type
   and bounds.first_race_id = inside.first_race_id
left join neighbours
    on bounds.driver_id = neighbours.driver_id
   and bounds.streak_type = neighbours.streak_type
   and bounds.first_race_id = neighbours.first_race_id
where bounds.first_number is null
   or bounds.last_number is null
   or bounds.last_number - bounds.first_number + 1 <> bounds.streak_length
   or coalesce(inside.qualifying_inside, 0) <> bounds.streak_length
   or coalesce(neighbours.neighbour_qualifies, false)
