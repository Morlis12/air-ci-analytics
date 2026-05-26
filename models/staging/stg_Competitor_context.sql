-- models/staging/stg_competitor_context.sql
with source as (
    select * from {{ source('excel_source', 'Competitor_context') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(market_id::varchar), '')                        as market_id,
        nullif(trim(route_id::varchar), '')                         as route_id,
        nullif(trim(competitor_name::varchar), '')                  as competitor_name,

        -- =========================================
        -- DONNÉES CONCURRENTIELLES
        -- =========================================
        competitor_frequency_weekly::integer                        as competitor_frequency_weekly,
        competitor_average_fare_usd::double                         as competitor_average_fare_usd,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- force concurrentielle sur la route
        -- basée sur la fréquence hebdomadaire
        case
            when competitor_frequency_weekly::integer >= 7  then 'very_strong'
            when competitor_frequency_weekly::integer >= 5  then 'strong'
            when competitor_frequency_weekly::integer >= 3  then 'moderate'
            else                                                 'weak'
        end                                                         as competitor_strength,

        -- segment tarifaire du concurrent
        case
            when competitor_average_fare_usd::double < 150  then 'low_cost'
            when competitor_average_fare_usd::double < 250  then 'mid_range'
            when competitor_average_fare_usd::double < 350  then 'premium'
            else                                                  'ultra_premium'
        end                                                         as competitor_fare_segment,

        -- nombre de concurrents sur la route
        -- (utile pour mesurer l'intensité concurrentielle)
        count(*) over (
            partition by route_id
        )                                                           as nb_competitors_on_route,

        -- fréquence totale concurrents sur la route
        sum(competitor_frequency_weekly::integer) over (
            partition by route_id
        )                                                           as total_competitor_frequency,

        -- fare moyen des concurrents sur la route
        round(avg(competitor_average_fare_usd::double) over (
            partition by route_id
        ), 2)                                                       as avg_competitor_fare_on_route,

        -- fare min des concurrents sur la route
        min(competitor_average_fare_usd::double) over (
            partition by route_id
        )                                                           as min_competitor_fare_on_route,

        -- fare max des concurrents sur la route
        max(competitor_average_fare_usd::double) over (
            partition by route_id
        )                                                           as max_competitor_fare_on_route,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when market_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when route_id is null
            then true else false
        end                                                         as is_route_missing,

        case
            when competitor_name is null
            then true else false
        end                                                         as is_competitor_missing,

        case
            when competitor_frequency_weekly::integer <= 0
            then true else false
        end                                                         as is_frequency_invalid,

        case
            when competitor_average_fare_usd::double <= 0
            then true else false
        end                                                         as is_fare_invalid

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_route_missing = false
    and is_competitor_missing = false
)

select * from final