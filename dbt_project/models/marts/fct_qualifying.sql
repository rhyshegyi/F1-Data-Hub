-- One row per driver per qualifying session, 1994 to present: the source for
-- the qualifying table on the Race Weekend page.
--
-- Built from qualifying rather than race results, so a driver who qualified
-- but didn't start still appears. Their grid_position is null.
--
-- Times are kept as the source writes them (1:29.179) for display, and in
-- seconds for sorting and arithmetic. Before 2006 there was one timed session,
-- recorded as Q1, and final_session is null.
--
-- gap_seconds compares each driver's lap in the last session they set a time
-- in with the fastest lap in that same session. For anyone who reached Q3 it
-- is the gap to pole. Comparing laps across sessions misleads:
--   * at Bahrain 2024 Leclerc's Q2 lap beat Verstappen's pole lap in Q3, so P2
--     came out 0.014s ahead of pole;
--   * in 2008 and 2009 Q3 was run on race fuel, a second or more slower than
--     Q1 and Q2;
--   * at the 2012 British Grand Prix Q1 was dry and Q3 wet, so every Q1
--     knockout looked 20 seconds faster than pole.
-- Within one session none of that applies, and the gap can't be negative.
--
-- The first six races of 2005 used aggregate qualifying: a Saturday lap and a
-- Sunday lap, added together, lowest total on pole. The source stores the two
-- laps as Q1 and Q2, so for those drivers the session time is their sum. At
-- Australia 2005 Webber's Sunday lap alone was quicker than Fisichella's, but
-- Fisichella's total was 3.5 seconds better, and he took pole.

with source as (

    select
        *,
        season = 2005 and q1_seconds is not null and q2_seconds is not null as is_aggregate
    from {{ ref('stg_jolpica__qualifying') }}

),

qualifying as (

    select
        *,
        least(q1_seconds, q2_seconds, q3_seconds) as best_qualifying_seconds,
        case
            when is_aggregate then q1_seconds + q2_seconds
            else coalesce(q3_seconds, q2_seconds, q1_seconds)
        end as final_session_seconds,
        case
            when is_aggregate then 'Aggregate'
            when q3_seconds is not null then 'Q3'
            when q2_seconds is not null then 'Q2'
            when q1_seconds is not null then 'Q1'
        end as timed_session
    from source

),

grid as (

    select season, round, driver_id, min(grid_position) as grid_position
    from {{ ref('int_results_joined_to_qualifying') }}
    group by season, round, driver_id

),

with_session_best as (

    select
        *,
        min(final_session_seconds)
            over (partition by season, round, timed_session) as session_best_seconds
    from qualifying

)

select
    {{ race_id('q.season', 'q.round') }} as race_id,
    q.driver_id,
    q.constructor_id,

    q.qualifying_position,
    q.q1_time,
    q.q2_time,
    q.q3_time,
    q.q1_seconds,
    q.q2_seconds,
    q.q3_seconds,
    q.best_qualifying_seconds,
    q.final_session_seconds,
    q.final_session_seconds - q.session_best_seconds as gap_seconds,

    -- Knockout qualifying began in 2006. Before that the source's Q1 and Q2
    -- are single or aggregate sessions, not knockout rounds.
    case when q.season >= 2006 then q.timed_session end as final_session,

    grid.grid_position

from with_session_best as q
left join grid
    on q.season = grid.season
   and q.round = grid.round
   and q.driver_id = grid.driver_id
