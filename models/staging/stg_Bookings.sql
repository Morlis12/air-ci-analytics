-- models/staging/stg_bookings.sql
with source as (
    select * from {{ source('excel_source', 'Bookings') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(booking_id::varchar), '')                       as booking_id,
        nullif(trim(customer_id::varchar), '')                      as customer_id,
        nullif(trim(flight_id::varchar), '')                        as flight_id,

        -- =========================================
        -- DATES
        -- =========================================
        booking_date::timestamp                                     as booked_at,
        booking_date::date                                          as booking_date,

        -- =========================================
        -- CANAL & TARIF
        -- =========================================
        nullif(trim(lower(booking_channel::varchar)), '')           as booking_channel,
        nullif(trim(lower(fare_class::varchar)), '')                as fare_class,
        nullif(trim(lower(fare_family::varchar)), '')               as fare_family,

        -- =========================================
        -- REVENUS
        -- =========================================
        ticket_price_usd::double                                    as ticket_price_usd,
        ancillary_revenue_usd::double                               as ancillary_revenue_usd,

        -- revenu total par booking
        round(
            ticket_price_usd::double + ancillary_revenue_usd::double, 2
        )                                                           as total_revenue_usd,

        -- =========================================
        -- SERVICES
        -- =========================================
        bags_count::integer                                         as bags_count,
        seat_selection_flag::integer = 1                            as has_seat_selection,

        -- =========================================
        -- STATUT
        -- =========================================
        nullif(trim(lower(booking_status::varchar)), '')            as booking_status,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- part du revenu ancillaire sur le total
        case
            when (ticket_price_usd::double + ancillary_revenue_usd::double) > 0
            then round(
                ancillary_revenue_usd::double /
                (ticket_price_usd::double + ancillary_revenue_usd::double) * 100
            , 2)
            else 0
        end                                                         as ancillary_revenue_pct,

        -- catégorie de valeur du ticket
        case
            when ticket_price_usd::double = 0        then 'free'
            when ticket_price_usd::double < 100      then 'low'
            when ticket_price_usd::double < 300      then 'medium'
            when ticket_price_usd::double < 600      then 'high'
            else 'premium'
        end                                                         as ticket_price_category,

        -- flags statut booking
        case
            when lower(booking_status::varchar) = 'confirmed'
            then true else false
        end                                                         as is_confirmed,

        case
            when lower(booking_status::varchar) = 'flown'
            then true else false
        end                                                         as is_flown,

        case
            when lower(booking_status::varchar) = 'cancelled'
            then true else false
        end                                                         as is_cancelled,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when booking_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when customer_id is null or flight_id is null
            then true else false
        end                                                         as is_fk_missing,

        case
            when ticket_price_usd::double < 0
            then true else false
        end                                                         as is_price_negative,

        case
            when ancillary_revenue_usd::double < 0
            then true else false
        end                                                         as is_ancillary_negative,

        case
            when bags_count::integer < 0
            then true else false
        end                                                         as is_bags_invalid,

        case
            when booking_date::date > current_date
            then true else false
        end                                                         as is_booking_future,

        case
            when ticket_price_usd::double > 10000
            then true else false
        end                                                         as is_price_suspect

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_fk_missing = false
)

select * from final