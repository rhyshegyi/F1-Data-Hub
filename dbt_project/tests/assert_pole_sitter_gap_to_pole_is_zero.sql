-- The pole-sitter set the fastest lap in the last session they took part in,
-- so their gap must be exactly zero, and no driver's gap can be negative.
-- Gaps are measured within a session, never across sessions: a race-fuel Q3
-- (2008 and 2009) or a wet Q3 would otherwise produce negative gaps.

select race_id, driver_id, qualifying_position, gap_seconds
from {{ ref('fct_qualifying') }}
where gap_seconds < 0
   or (qualifying_position = 1 and final_session_seconds is not null and not (gap_seconds <=> 0.0))
