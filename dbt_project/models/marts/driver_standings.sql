-- Final drivers' championship standings per season, widened with the season's
-- race statistics. One row per driver per season, 1950 to present.
--
-- The championship columns come from the source's published classification, not
-- from summing points scored. Those are different numbers before 1991, when
-- only a driver's best N results counted toward the title: Prost outscored
-- Senna 105 to 94 in 1988 and Hill outscored Surtees 41 to 40 in 1964, yet
-- Senna and Surtees are the champions. Both numbers are exposed here --
-- championship_points and points_scored -- precisely so the difference is
-- visible rather than hidden behind whichever one happened to be chosen.

with standings as (

    select * from {{ ref('stg_jolpica__driver_standings') }}

),

drivers as (

    select season, driver_id, full_name, driver_code, nationality
    from {{ ref('stg_jolpica__drivers') }}

),

season_stats as (

    select
        season,
        driver_id,
        count(distinct round)                                        as races_entered,
        sum(points)                                                  as points_scored,
        sum(case when finish_position = 1 then 1 else 0 end)          as race_wins,
        sum(case when finish_position <= 3 then 1 else 0 end)         as podiums,
        sum(case when qualifying_position = 1 then 1 else 0 end)      as poles,
        sum(case when not was_classified then 1 else 0 end)           as did_not_finish,
        avg(case when was_classified then finish_position end)        as avg_finish_position,
        avg(grid_position)                                            as avg_grid_position,
        sum(positions_gained)                                         as net_positions_gained

    from {{ ref('int_results_joined_to_qualifying') }}
    group by season, driver_id

),

sprint_points as (

    -- Sprints award championship points, so they have to be counted here or
    -- points_scored disagrees with the published standings from 2021 onwards.
    select
        season,
        driver_id,
        sum(points) as sprint_points
    from {{ ref('stg_jolpica__sprint_results') }}
    group by season, driver_id

)

select
    standings.season,
    standings.driver_id,
    drivers.full_name                        as driver_name,
    drivers.driver_code,
    drivers.nationality                      as driver_nationality,

    -- Constructors is an array: a driver who changed teams mid-season has more
    -- than one, and flattening it to a single value would pick one arbitrarily.
    standings.constructor_ids,
    array_join(standings.constructor_names, ', ') as constructor_names,

    -- As published.
    standings.championship_position,
    standings.championship_position_text,
    standings.championship_points,
    standings.wins                           as championship_wins,
    standings.championship_position = 1      as is_champion,

    -- As scored, races and sprints combined. Equal to championship_points from
    -- 1991 onwards, once dropped-score rules ended; lower before that.
    season_stats.points_scored + coalesce(sprint_points.sprint_points, 0)
        as points_scored,
    season_stats.points_scored               as race_points_scored,
    coalesce(sprint_points.sprint_points, 0) as sprint_points_scored,
    standings.championship_points
        - (season_stats.points_scored + coalesce(sprint_points.sprint_points, 0))
        as points_dropped,

    season_stats.races_entered,
    season_stats.race_wins,
    season_stats.podiums,
    season_stats.poles,
    season_stats.did_not_finish,
    round(season_stats.avg_finish_position, 2) as avg_finish_position,
    round(season_stats.avg_grid_position, 2)   as avg_grid_position,
    season_stats.net_positions_gained

from standings
left join drivers
    on standings.season = drivers.season
   and standings.driver_id = drivers.driver_id
left join season_stats
    on standings.season = season_stats.season
   and standings.driver_id = season_stats.driver_id
left join sprint_points
    on standings.season = sprint_points.season
   and standings.driver_id = sprint_points.driver_id
