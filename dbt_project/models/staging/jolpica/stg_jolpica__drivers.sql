-- One row per driver per season -- the grain the source publishes, since the
-- drivers endpoint is season-scoped. A driver who raced across fifteen seasons
-- appears fifteen times. Collapsing that to one row per driver is a decision
-- for the intermediate layer, not a fact about the source.

with pages as (

    select season, payload
    from {{ source('jolpica_raw', 'raw_jolpica_drivers') }}

),

exploded as (

    select pages.season, driver
    from pages
    lateral view explode(
        from_json(payload:MRData.DriverTable.Drivers, '{{ jolpica_drivers_schema() }}')
    ) exploded_drivers as driver

)

select
    try_cast(season as int)                 as season,
    driver.driverId                     as driver_id,

    -- Both absent for most of the sport's history: three-letter codes appear
    -- from the 1990s, permanent numbers only from 2014.
    driver.code                         as driver_code,
    try_cast(driver.permanentNumber as int) as permanent_number,

    driver.givenName                    as given_name,
    driver.familyName                   as family_name,
    concat_ws(' ', driver.givenName, driver.familyName) as full_name,
    try_cast(driver.dateOfBirth as date)    as date_of_birth,
    driver.nationality                  as nationality,
    driver.url                          as wikipedia_url

from exploded
