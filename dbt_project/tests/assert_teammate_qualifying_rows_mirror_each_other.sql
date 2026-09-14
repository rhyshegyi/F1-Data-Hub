-- The two rows for a pair of teammates must describe the same comparison from
-- opposite sides: each names the other as teammate, both compare the same
-- session, the gaps cancel out, and exactly one of them beat the other.

with pairs as (

    select * from {{ ref('int_teammate_qualifying') }}

)

select
    mine.season,
    mine.round,
    mine.driver_id,
    mine.teammate_id,
    mine.session_compared,
    theirs.session_compared as teammate_session_compared,
    mine.gap_seconds,
    theirs.gap_seconds      as teammate_gap_seconds,
    mine.beat_teammate,
    theirs.beat_teammate    as teammate_beat_teammate
from pairs as mine
left join pairs as theirs
    on mine.season = theirs.season
   and mine.round = theirs.round
   and mine.constructor_id = theirs.constructor_id
   and mine.teammate_id = theirs.driver_id
   and mine.driver_id = theirs.teammate_id
where theirs.driver_id is null
   or not (mine.session_compared <=> theirs.session_compared)
   or not (mine.gap_seconds <=> (-theirs.gap_seconds))
   or not (mine.beat_teammate <=> (not theirs.beat_teammate))
