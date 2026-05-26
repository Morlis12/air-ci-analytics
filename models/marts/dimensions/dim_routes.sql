with routes as (
    select * from {{ ref('stg_Routes') }}
),

origin_airports as (
    select
        airport_code,
        airport_name        as origin_airport_name,
        city                as origin_city,
        country             as origin_country,
        continent           as origin_continent,
        is_domestic         as origin_is_domestic,
        is_international    as origin_is_international
    from {{ ref('stg_Airports') }}
),

destination_airports as (
    select
        airport_code,
        airport_name        as destination_airport_name,
        city                as destination_city,
        country             as destination_country,
        continent           as destination_continent,
        is_domestic         as destination_is_domestic,
        is_international    as destination_is_international
    from {{ ref('stg_Airports') }}
),

competitor_agg as (
    select
        route_id,
        count(*)                                    as nb_competitors,
        round(avg(competitor_average_fare_usd), 2)  as avg_competitor_fare_usd,
        min(competitor_average_fare_usd)            as min_competitor_fare_usd,
        max(competitor_average_fare_usd)            as max_competitor_fare_usd,
        sum(competitor_frequency_weekly)            as total_competitor_frequency,
        max(competitor_frequency_weekly)            as max_competitor_strength
    from {{ ref('stg_Competitor_context') }}
    group by route_id
),

final as (
    select
        r.route_id,
        r.route_key,
        r.origin_airport_code,
        r.destination_airport_code,
        r.route_type,
        r.distance_km,
        r.distance_category,
        r.block_time_min,
        r.block_time_hours,
        r.avg_speed_kmh,
        r.is_return_route,

        oa.origin_airport_name,
        oa.origin_city,
        oa.origin_country,
        oa.origin_continent,
        oa.origin_is_domestic,

        da.destination_airport_name,
        da.destination_city,
        da.destination_country,
        da.destination_continent,
        da.destination_is_domestic,

        coalesce(c.nb_competitors, 0)               as nb_competitors,
        c.avg_competitor_fare_usd,
        c.min_competitor_fare_usd,
        c.max_competitor_fare_usd,
        coalesce(c.total_competitor_frequency, 0)   as total_competitor_frequency,

        case
            when coalesce(c.nb_competitors, 0) = 0     then 'monopole'
            when coalesce(c.nb_competitors, 0) = 1     then 'duopole'
            when coalesce(c.nb_competitors, 0) <= 3    then 'oligopole'
            else                                             'haute_concurrence'
        end                                             as competitive_intensity,

        case
            when r.route_type = 'international'
            or r.distance_category = 'long_haul'
            then true else false
        end                                             as is_strategic_route

    from routes r
    left join origin_airports oa
        on oa.airport_code = r.origin_airport_code
    left join destination_airports da
        on da.airport_code = r.destination_airport_code
    left join competitor_agg c
        on c.route_id = r.route_id
)

select * from final
