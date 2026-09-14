-- Power BI's Field value formatting silently ignores anything that isn't a
-- valid colour, so a typo would leave a cell uncoloured without any error.

select constructor_id, team_colour
from {{ ref('team_colours') }}
where not team_colour rlike '^#[0-9A-F]{6}$'
