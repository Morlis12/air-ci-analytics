with source as (
    select * from {{ source('excel_source', 'Flights') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        flight_id::varchar                                          as flight_id,
        nullif(trim(flight_number::varchar), '')                    as flight_number,
        nullif(trim(route_id::varchar), '')                         as route_id,


        -- CORRECTION : Utilisation des fonctions sur la source brute pour éviter le conflit d'alias
        coalesce(flight_id::varchar, '')
            || '|' || coalesce(nullif(trim(route_id::varchar), ''), '')
            || '|' || coalesce(flight_date::varchar, '')            as flight_cost_key,

        -- =========================================
        -- DATES & HEURES
        -- =========================================
        flight_date::date                                           as flight_date,
        scheduled_departure::timestamp                              as scheduled_departure_at,
        actual_departure::timestamp                                 as actual_departure_at,
        scheduled_arrival::timestamp                                as scheduled_arrival_at,
        actual_arrival::timestamp                                   as actual_arrival_at,

        -- =========================================
        -- AVION & CAPACITÉ
        -- =========================================
        nullif(trim(aircraft_type::varchar), '')                    as aircraft_type,
        seat_capacity::integer                                      as seat_capacity,

        -- =========================================
        -- STATUT & PERFORMANCE
        -- =========================================
        nullif(trim(lower(flight_status::varchar)), '')             as flight_status,
        delay_min::integer                                          as delay_minutes,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================
        datediff(
            'minute',
            scheduled_departure::timestamp,
            actual_departure::timestamp
        )                                                           as computed_departure_delay_min,

        datediff(
            'minute',
            scheduled_arrival::timestamp,
            actual_arrival::timestamp
        )                                                           as computed_arrival_delay_min,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when flight_id is null 
            then true else false
        end                                                         as is_id_missing,

        case
            when delay_min::integer >= 15 
            then true else false
        end                                                         as is_delayed,

        case
            when lower(flight_status::varchar) = 'cancelled' 
            then true else false
        end                                                         as is_cancelled,

        case
            when actual_arrival::timestamp < actual_departure::timestamp 
            then true else false
        end                                                         as is_timeline_invalid,

        case
            when delay_min::integer > 1440 
            then true else false
        end                                                         as is_delay_suspect,

        case
            when seat_capacity::integer <= 0 
            then true else false
        end                                                         as is_capacity_invalid

    from source
),

-- =========================================
-- FILTRE FINAL : on exclut les lignes sans ID
-- =========================================
final as (
    select * from renamed
    where is_id_missing = false
)

select * from final
