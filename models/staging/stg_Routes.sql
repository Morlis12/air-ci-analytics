-- models/staging/stg_routes.sql
with source as (
    select * from {{ source('excel_source', 'Routes') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(route_id::varchar), '')                         as route_id,
        nullif(trim(origin_airport_code::varchar), '')              as origin_airport_code,
        nullif(trim(destination_airport_code::varchar), '')         as destination_airport_code,

        -- =========================================
        -- CARACTÉRISTIQUES DE LA ROUTE
        -- =========================================
        nullif(trim(lower(route_type::varchar)), '')                as route_type,
        distance_km::integer                                        as distance_km,
        block_time_min::integer                                     as block_time_min,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- vitesse commerciale moyenne en km/h
        round(
            (distance_km::double / block_time_min::double) * 60, 1
        )                                                           as avg_speed_kmh,

        -- block time en heures (plus lisible pour les dashboards)
        round(block_time_min::double / 60, 2)                       as block_time_hours,

        -- route inverse (utile pour les jointures aller-retour)
        trim(destination_airport_code::varchar) 
            || '-' || 
        trim(origin_airport_code::varchar)                          as reverse_route_key,

        -- clé de route canonique (toujours dans le même sens)
        trim(origin_airport_code::varchar) 
            || '-' || 
        trim(destination_airport_code::varchar)                     as route_key,

        -- =========================================
        -- FLAGS MÉTIER
        -- =========================================

        -- flag route retour (ex: ACC→ABJ est le retour de ABJ→ACC)
        case
            when origin_airport_code::varchar != 'ABJ'
            then true else false
        end                                                         as is_return_route,

        -- catégories de distance
        case
            when distance_km::integer < 500                 then 'short_haul'
            when distance_km::integer between 500 and 1500  then 'medium_haul'
            when distance_km::integer > 1500                then 'long_haul'
        end                                                         as distance_category,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when route_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when origin_airport_code is null
            or destination_airport_code is null
            then true else false
        end                                                         as is_airport_missing,

        case
            when distance_km::integer <= 0
            then true else false
        end                                                         as is_distance_invalid,

        case
            when block_time_min::integer <= 0
            then true else false
        end                                                         as is_blocktime_invalid,

        -- cohérence vitesse : un avion commercial = 600-950 km/h
        case
            when round((distance_km::double / block_time_min::double) * 60, 1)
                not between 300 and 1000
            then true else false
        end                                                         as is_speed_suspect

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_airport_missing = false
)

select * from final