-- One row per driver across their whole career.
--
-- Staging keeps drivers at the grain the source publishes -- one row per
-- driver per season -- and deliberately left collapsing them to here. A
-- dimension needs one row per key, so each attribute takes its most recent
-- value.
--
-- "Most recent non-null" for code and number specifically: both are absent for
-- most of the sport's history, and a driver whose final season somehow lacked
-- one should not lose the value they carried before. max_by ignores rows whose
-- ordering value is null, which is what the case expressions exploit.

with driver_seasons as (

    select * from {{ ref('stg_jolpica__drivers') }}

)

select
    driver_id,

    max_by(full_name, season)             as driver_name,
    max_by(given_name, season)            as given_name,
    max_by(family_name, season)           as family_name,

    max_by(driver_code,
           case when driver_code is not null then season end)      as driver_code,
    max_by(permanent_number,
           case when permanent_number is not null then season end) as permanent_number,

    max_by(date_of_birth, season)         as date_of_birth,
    max_by(nationality, season)           as nationality,
    max_by(wikipedia_url, season)         as wikipedia_url,

    min(season)                           as first_season,
    max(season)                           as last_season,
    count(*)                              as seasons_entered

from driver_seasons
group by driver_id
