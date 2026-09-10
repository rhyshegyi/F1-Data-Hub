-- The source mixes lap times ("1:29.179") with race durations ("1:31:44.742")
-- and gives no signal which to expect, so the macro must recognise both.
-- A driver who set no time must come out null, never zero.
with cases as (
    select '1:29.179'    as source_time, 89.179   as expected_seconds
    union all select '1:31:44.742',       5504.742
    union all select '0:59.999',          59.999
    union all select '59.999',            59.999
    union all select '2:00:00.000',       7200.0
    union all select cast(null as string), cast(null as double)
    union all select '',                   cast(null as double)
    union all select 'no time',            cast(null as double)
)
select source_time, expected_seconds, {{ parse_lap_time('source_time') }} as actual_seconds
from cases
where not (round({{ parse_lap_time('source_time') }}, 3) <=> expected_seconds)
