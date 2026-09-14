-- One row per driver per qualifying session, compared with their teammate,
-- 1994 to present. The source for the Teammate Battles page.
--
-- teammate_name is the one descriptive column on a fact. The driver side
-- reaches dim_driver through driver_id; a second relationship from teammate_id
-- to the same dimension would have to be inactive in Power BI, so every visual
-- would need USERELATIONSHIP just to show a name. Carrying the name here is the
-- simpler model.

with pairs as (

    select * from {{ ref('int_teammate_qualifying') }}

),

drivers as (

    select driver_id, driver_name from {{ ref('dim_driver') }}

)

select
    {{ race_id('pairs.season', 'pairs.round') }} as race_id,
    pairs.driver_id,
    pairs.constructor_id,
    pairs.teammate_id,
    teammates.driver_name as teammate_name,

    pairs.qualifying_position,
    pairs.teammate_qualifying_position,
    pairs.beat_teammate,

    pairs.session_compared,
    pairs.qualifying_seconds,
    pairs.teammate_qualifying_seconds,
    pairs.gap_seconds,
    pairs.gap_pct

from pairs
left join drivers as teammates
    on pairs.teammate_id = teammates.driver_id
