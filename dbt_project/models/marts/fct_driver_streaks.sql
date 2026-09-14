-- One row per streak: an unbroken run of wins, podiums or points finishes by one
-- driver.
--
-- Streaks run over a driver's consecutive starts, not consecutive calendar
-- races, which is how F1 records count them: a race the driver missed doesn't
-- break a streak. A points finish means scoring under the points system of the
-- time, so the target moves from the top five in the 1950s to the top ten now.
--
-- Built as gaps and islands: number each driver's starts, keep the ones that
-- qualify, and subtract a second numbering over just those. Starts in the same
-- unbroken run share the difference.

with starts as (

    select
        driver_id,
        race_id,
        race_date,
        won,
        podium,
        scored_points,
        row_number() over (partition by driver_id order by race_date, race_id) as start_number,
        count(*) over (partition by driver_id)                                 as career_starts
    from {{ ref('int_driver_race') }}

),

qualifying_starts as (

    select driver_id, race_id, race_date, start_number, career_starts, 'win' as streak_type
    from starts where won
    union all
    select driver_id, race_id, race_date, start_number, career_starts, 'podium'
    from starts where podium
    union all
    select driver_id, race_id, race_date, start_number, career_starts, 'points'
    from starts where scored_points

),

islands as (

    select
        *,
        start_number - row_number() over (
            partition by driver_id, streak_type order by start_number
        ) as island
    from qualifying_starts

),

streaks as (

    select
        driver_id,
        streak_type,
        count(*)                          as streak_length,
        min_by(race_id, start_number)     as first_race_id,
        max_by(race_id, start_number)     as last_race_id,
        min(race_date)                    as first_race_date,
        max(race_date)                    as last_race_date,
        max(start_number) = max(career_starts) as runs_to_latest_start
    from islands
    group by driver_id, streak_type, island

),

races as (

    select
        {{ race_id('season', 'round') }} as race_id,
        season,
        race_name
    from {{ ref('stg_jolpica__races') }}

)

select
    streaks.driver_id,
    streaks.streak_type,
    streaks.streak_length,
    -- Ranked within the type so a report can show the top ten streaks. A Top N
    -- filter on the driver would merge a driver's separate streaks into one.
    rank() over (
        partition by streaks.streak_type order by streaks.streak_length desc
    ) as streak_rank,
    streaks.first_race_id,
    streaks.last_race_id,
    streaks.first_race_date,
    streaks.last_race_date,
    concat(first_race.season, ' ', first_race.race_name) as first_race,
    concat(last_race.season, ' ', last_race.race_name)   as last_race,
    streaks.runs_to_latest_start

from streaks
left join races as first_race
    on streaks.first_race_id = first_race.race_id
left join races as last_race
    on streaks.last_race_id = last_race.race_id
