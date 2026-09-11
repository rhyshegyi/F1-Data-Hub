-- One row per race on the calendar, 1950 to present, including rounds of the
-- current season that have not been run yet.
--
-- has_results separates those future rounds from completed ones, so the
-- dashboard can show the calendar without charting empty races as zeroes.

with races as (

    select * from {{ ref('stg_jolpica__races') }}

),

completed as (

    select distinct season, round
    from {{ ref('stg_jolpica__results') }}

)

select
    {{ race_id('races.season', 'races.round') }} as race_id,

    races.season,
    races.round,
    races.race_name,

    -- What slicers and axes should display. race_name can't be put in race
    -- order in Power BI: "British Grand Prix" appears in 77 seasons with 77
    -- different race_ids, and Sort by column needs each value to map to one
    -- sort key. Embedding the round makes every label map to exactly one
    -- round, and zero-padding it means the label sorts correctly as plain
    -- text as well.
    format_string('R%02d · %s', races.round, races.race_name) as race_label,

    races.race_date,
    races.race_start_utc,

    races.circuit_id,
    races.circuit_name,
    races.circuit_locality,
    races.circuit_country,
    races.circuit_latitude,
    races.circuit_longitude,

    completed.round is not null          as has_results,
    -- From the schedule, not from sprint results, so an upcoming sprint
    -- weekend is flagged before it has been run.
    races.sprint_date is not null        as is_sprint_weekend,

    races.wikipedia_url

from races
left join completed
    on races.season = completed.season
   and races.round = completed.round
