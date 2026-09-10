-- A null championship position must always be explained by a non-numeric
-- classification code, and a numeric code must always parse to a position.
-- Anything else means try_cast silently swallowed a value it should not have.

with combined as (

    select championship_position, championship_position_text
    from {{ ref('stg_jolpica__driver_standings') }}
    union all
    select championship_position, championship_position_text
    from {{ ref('stg_jolpica__constructor_standings') }}

)

select *
from combined
where (championship_position is null) <> (not championship_position_text rlike '^[0-9]+$')
