-- One row per championship season, 1950 to present.
--
-- The hub a season slicer hangs off. Races relate to it through dim_race and
-- standings relate to it directly, so one slicer filters both without giving
-- Power BI two competing paths to the same fact.

with races as (

    select season, round, race_date, sprint_date
    from {{ ref('stg_jolpica__races') }}

),

completed as (

    select distinct season, round
    from {{ ref('stg_jolpica__results') }}

),

sprints as (

    select distinct season, round
    from {{ ref('stg_jolpica__sprint_results') }}

),

latest as (

    select max(season) as current_season from races

)

select
    races.season,

    count(*)                             as races_scheduled,
    count(completed.round)               as races_completed,
    count(races.sprint_date)             as sprint_weekends_scheduled,
    count(sprints.round)                 as sprints_completed,
    min(races.race_date)                 as first_race_date,
    max(races.race_date)                 as last_race_date,

    -- The era in which championship points and points scored diverge, because
    -- only a driver's best N results counted toward the title.
    races.season <= 1990                 as is_dropped_scores_era,

    races.season = max(latest.current_season) as is_current_season

from races
cross join latest
left join completed
    on races.season = completed.season
   and races.round = completed.round
left join sprints
    on races.season = sprints.season
   and races.round = sprints.round
group by races.season
