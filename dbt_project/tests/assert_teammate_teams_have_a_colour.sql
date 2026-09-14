-- Every team on the Teammate Battles page must have a colour. A new team joining
-- the grid fails the build here, rather than appearing in the report as the
-- grey fallback that nobody notices.

select distinct fct.constructor_id
from {{ ref('fct_teammate_qualifying') }} as fct
left join {{ ref('team_colours') }} as colours
    on fct.constructor_id = colours.constructor_id
where colours.constructor_id is null
