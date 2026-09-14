-- Teammates are compared in the last session both of them set a time in, so a
-- driver knocked out in Q1 is never measured against a teammate's Q3 lap on a
-- faster track.
--
-- A row fails if both drivers had a time in a later session than the one
-- compared, if either driver has no time in the session compared, or if a pair
-- that shared a timed session was left uncompared.

with pairs as (

    select * from {{ ref('int_teammate_qualifying') }}

),

qualifying as (

    select * from {{ ref('stg_jolpica__qualifying') }}

),

both_timed as (

    select
        pairs.season,
        pairs.round,
        pairs.driver_id,
        pairs.teammate_id,
        pairs.session_compared,
        driver.q1_seconds is not null and teammate.q1_seconds is not null as both_q1,
        driver.q2_seconds is not null and teammate.q2_seconds is not null as both_q2,
        driver.q3_seconds is not null and teammate.q3_seconds is not null as both_q3
    from pairs
    inner join qualifying as driver
        on pairs.season = driver.season
       and pairs.round = driver.round
       and pairs.driver_id = driver.driver_id
    inner join qualifying as teammate
        on pairs.season = teammate.season
       and pairs.round = teammate.round
       and pairs.teammate_id = teammate.driver_id

)

select *
from both_timed
where (session_compared is null and (both_q1 or both_q2 or both_q3))
   or (session_compared = 'Q1' and (not both_q1 or both_q2 or both_q3))
   or (session_compared = 'Q2' and (not both_q2 or both_q3))
   or (session_compared = 'Q3' and not both_q3)
