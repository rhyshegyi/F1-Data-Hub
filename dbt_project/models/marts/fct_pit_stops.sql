-- One row per pit stop, 2011 to present: the source for the pit stops table
-- beside the position chart.
--
-- duration_seconds is time in the pit lane, entry to exit, not just the time
-- the car was stationary.

select
    {{ race_id('season', 'round') }} as race_id,
    driver_id,
    stop_number,
    lap,
    time_of_day,
    duration_seconds
from {{ ref('stg_jolpica__pit_stops') }}
