-- One row per driver across their whole career: totals, rates, an era-adjusted
-- score and age records. The source for the Records Hub page.
--
-- Totals favour modern drivers, who race 20-plus Grands Prix a season against
-- 7 or 8 in the 1950s, so every total sits next to a rate. modern_points_per_start
-- is the era-adjusted score: every result rescored with today's points system,
-- divided by starts, which removes both points-system changes and season
-- length. It does not remove the car -- a dominant car still inflates it.
--
-- Titles are counted from fct_driver_standings, where a season only has a
-- champion once its final race has been run. A title's age is the driver's age
-- at that season's final race.

with starts as (

    select * from {{ ref('int_driver_race') }}

),

drivers as (

    select driver_id, date_of_birth from {{ ref('dim_driver') }}

),

season_finales as (

    select season, max(race_date) as final_race_date
    from starts
    group by season

),

titles as (

    select
        standings.driver_id,
        count(*)                            as titles,
        min(season_finales.final_race_date) as first_title_date,
        max(season_finales.final_race_date) as last_title_date,
        min(standings.season)               as first_title_season,
        max(standings.season)               as last_title_season
    from {{ ref('fct_driver_standings') }} as standings
    inner join season_finales
        on standings.season = season_finales.season
    where standings.is_champion
    group by standings.driver_id

),

careers as (

    select
        driver_id,
        min(season)                                         as first_season,
        max(season)                                         as last_season,
        count(*)                                            as starts,
        sum(case when won then 1 else 0 end)                as wins,
        sum(case when podium then 1 else 0 end)             as podiums,
        sum(case when pole then 1 else 0 end)               as poles,
        sum(case when scored_points then 1 else 0 end)      as points_finishes,
        sum(modern_points)                                  as modern_points,

        min(case when won then race_date end)               as first_win_date,
        max(case when won then race_date end)               as last_win_date,
        min(case when podium then race_date end)            as first_podium_date,
        max(case when podium then race_date end)            as last_podium_date

    from starts
    group by driver_id

)

select
    careers.driver_id,
    careers.first_season,
    careers.last_season,

    careers.starts,
    careers.wins,
    careers.podiums,
    careers.poles,
    careers.points_finishes,
    coalesce(titles.titles, 0)                          as titles,

    careers.wins / careers.starts                       as win_rate,
    careers.podiums / careers.starts                    as podium_rate,
    careers.poles / careers.starts                      as pole_rate,

    careers.modern_points,
    careers.modern_points / careers.starts              as modern_points_per_start,

    careers.first_win_date,
    careers.last_win_date,
    careers.first_podium_date,
    careers.last_podium_date,
    titles.first_title_season,
    titles.last_title_season,

    datediff(careers.first_win_date, drivers.date_of_birth)    as age_first_win_days,
    datediff(careers.last_win_date, drivers.date_of_birth)     as age_last_win_days,
    datediff(careers.first_podium_date, drivers.date_of_birth) as age_first_podium_days,
    datediff(careers.last_podium_date, drivers.date_of_birth)  as age_last_podium_days,
    datediff(titles.first_title_date, drivers.date_of_birth)   as age_first_title_days,
    datediff(titles.last_title_date, drivers.date_of_birth)    as age_last_title_days,

    {{ age_label('careers.first_win_date', 'drivers.date_of_birth') }}    as age_first_win,
    {{ age_label('careers.last_win_date', 'drivers.date_of_birth') }}     as age_last_win,
    {{ age_label('careers.first_podium_date', 'drivers.date_of_birth') }} as age_first_podium,
    {{ age_label('careers.last_podium_date', 'drivers.date_of_birth') }}  as age_last_podium,
    {{ age_label('titles.first_title_date', 'drivers.date_of_birth') }}   as age_first_title,
    {{ age_label('titles.last_title_date', 'drivers.date_of_birth') }}    as age_last_title

from careers
left join titles
    on careers.driver_id = titles.driver_id
left join drivers
    on careers.driver_id = drivers.driver_id
