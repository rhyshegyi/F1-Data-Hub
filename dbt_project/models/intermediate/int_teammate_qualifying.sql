-- One row per driver per qualifying session, paired with their teammate.
--
-- Teammates are compared in the last session both of them set a time in. Taking
-- each driver's best lap instead would measure a driver knocked out in Q1
-- against a teammate's Q3 lap, set later on a track with more grip, and credit
-- the teammate with a gap that is mostly track evolution.
--
-- Qualifying only exists from 1994. Every team since then has run at most two
-- cars in a session, so pairing within a constructor is unambiguous; the 38
-- one-car entries have no teammate and drop out here.

with qualifying as (

    select * from {{ ref('stg_jolpica__qualifying') }}

),

two_car_entries as (

    select qualifying.*
    from qualifying
    inner join (
        select season, round, constructor_id
        from qualifying
        group by season, round, constructor_id
        having count(*) = 2
    ) as two_car_teams
        on qualifying.season = two_car_teams.season
       and qualifying.round = two_car_teams.round
       and qualifying.constructor_id = two_car_teams.constructor_id

),

paired as (

    select
        driver.season,
        driver.round,
        driver.constructor_id,
        driver.driver_id,
        teammate.driver_id           as teammate_id,
        driver.qualifying_position,
        teammate.qualifying_position as teammate_qualifying_position,

        case
            when driver.q3_seconds is not null and teammate.q3_seconds is not null then 'Q3'
            when driver.q2_seconds is not null and teammate.q2_seconds is not null then 'Q2'
            when driver.q1_seconds is not null and teammate.q1_seconds is not null then 'Q1'
        end as session_compared,

        driver.q1_seconds,
        driver.q2_seconds,
        driver.q3_seconds,
        teammate.q1_seconds as teammate_q1_seconds,
        teammate.q2_seconds as teammate_q2_seconds,
        teammate.q3_seconds as teammate_q3_seconds

    from two_car_entries as driver
    inner join two_car_entries as teammate
        on driver.season = teammate.season
       and driver.round = teammate.round
       and driver.constructor_id = teammate.constructor_id
       and driver.driver_id <> teammate.driver_id

),

compared as (

    select
        *,
        case session_compared
            when 'Q3' then q3_seconds
            when 'Q2' then q2_seconds
            when 'Q1' then q1_seconds
        end as qualifying_seconds,
        case session_compared
            when 'Q3' then teammate_q3_seconds
            when 'Q2' then teammate_q2_seconds
            when 'Q1' then teammate_q1_seconds
        end as teammate_qualifying_seconds
    from paired

)

select
    season,
    round,
    constructor_id,
    driver_id,
    teammate_id,

    qualifying_position,
    teammate_qualifying_position,

    session_compared,
    qualifying_seconds,
    teammate_qualifying_seconds,

    qualifying_seconds - teammate_qualifying_seconds as gap_seconds,
    (qualifying_seconds - teammate_qualifying_seconds)
        / least(qualifying_seconds, teammate_qualifying_seconds) * 100 as gap_pct,

    qualifying_position < teammate_qualifying_position as beat_teammate

from compared
