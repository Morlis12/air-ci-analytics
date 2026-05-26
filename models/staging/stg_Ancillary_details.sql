-- models/staging/stg_ancillary_details.sql
with source as (
    select * from {{ source('excel_source', 'Ancillary_details') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(ancillary_id::varchar), '')                     as ancillary_id,
        nullif(trim(booking_id::varchar), '')                       as booking_id,

        -- =========================================
        -- CATÉGORIE & CANAL
        -- =========================================
        nullif(trim(item_category::varchar), '')                    as item_category,
        nullif(trim(lower(purchase_channel::varchar)), '')          as purchase_channel,

        -- =========================================
        -- REVENU
        -- =========================================
        item_revenue_usd::double                                    as item_revenue_usd,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- catégorie normalisée pour les marts
        -- (les noms peuvent varier dans l'Excel)
        case
            when lower(item_category::varchar) like '%bagage%'
            then 'baggage'
            when lower(item_category::varchar) like '%siège%'
            or lower(item_category::varchar) like '%siege%'
            then 'seat'
            when lower(item_category::varchar) like '%repas%'
            or lower(item_category::varchar) like '%meal%'
            then 'meal'
            when lower(item_category::varchar) like '%lounge%'
            then 'lounge'
            when lower(item_category::varchar) like '%assurance%'
            then 'insurance'
            when lower(item_category::varchar) like '%priorité%'
            or lower(item_category::varchar) like '%priority%'
            then 'priority'
            else 'other'
        end                                                         as item_category_normalized,

        -- canal normalisé
        case
            when lower(purchase_channel::varchar) like '%mobile%'
            or lower(purchase_channel::varchar) like '%application%'
            then 'mobile_app'
            when lower(purchase_channel::varchar) like '%site%'
            or lower(purchase_channel::varchar) like '%web%'
            then 'web'
            when lower(purchase_channel::varchar) like '%comptoir%'
            or lower(purchase_channel::varchar) like '%aéroport%'
            then 'airport_counter'
            when lower(purchase_channel::varchar) like '%agence%'
            or lower(purchase_channel::varchar) like '%travel%'
            then 'travel_agency'
            else 'other'
        end                                                         as purchase_channel_normalized,

        -- flag achat digital vs physique
        case
            when lower(purchase_channel::varchar) like '%mobile%'
            or lower(purchase_channel::varchar) like '%application%'
            or lower(purchase_channel::varchar) like '%site%'
            or lower(purchase_channel::varchar) like '%web%'
            then true else false
        end                                                         as is_digital_purchase,

        -- flag siège premium (issue de secours = plus cher)
        case
            when lower(item_category::varchar) like '%issue de secours%'
            or lower(item_category::varchar) like '%premium%'
            then true else false
        end                                                         as is_premium_seat,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when ancillary_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when booking_id is null
            then true else false
        end                                                         as is_fk_missing,

        case
            when item_revenue_usd::double <= 0
            then true else false
        end                                                         as is_revenue_invalid,

        -- un article ancillaire > 500 USD = suspect
        case
            when item_revenue_usd::double > 500
            then true else false
        end                                                         as is_revenue_suspect

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_fk_missing = false
)

select * from final