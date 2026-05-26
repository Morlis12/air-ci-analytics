-- models/staging/stg_loyalty_activity.sql
with source as (
    select * from {{ source('excel_source', 'Loyalty_activity') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(activity_id::varchar), '')                      as activity_id,
        nullif(trim(customer_id::varchar), '')                      as customer_id,

        -- =========================================
        -- ACTIVITÉ
        -- =========================================
        nullif(trim(activity_type::varchar), '')                    as activity_type,
        miles_amount::integer                                       as miles_amount,
        estimated_value_usd::double                                 as estimated_value_usd,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- valeur par mile (rentabilité du programme)
        case
            when miles_amount::integer > 0
            then round(
                estimated_value_usd::double / miles_amount::integer
            , 4)
            else null
        end                                                         as value_per_mile_usd,

        -- catégorie d'activité normalisée
        case
            when lower(activity_type::varchar) like '%vol%'
            and lower(activity_type::varchar) like '%gagn%'
            then 'earn_flight'
            when lower(activity_type::varchar) like '%partenaire%'
            or lower(activity_type::varchar) like '%hôtel%'
            or lower(activity_type::varchar) like '%hotel%'
            then 'earn_partner'
            when lower(activity_type::varchar) like '%bonus%'
            or lower(activity_type::varchar) like '%promotion%'
            then 'earn_bonus'
            when lower(activity_type::varchar) like '%acheté%'
            or lower(activity_type::varchar) like '%achet%'
            then 'purchase'
            when lower(activity_type::varchar) like '%utilisé%'
            or lower(activity_type::varchar) like '%utilis%'
            or lower(activity_type::varchar) like '%dépensé%'
            then 'redeem'
            when lower(activity_type::varchar) like '%expiré%'
            or lower(activity_type::varchar) like '%expir%'
            then 'expire'
            else 'other'
        end                                                         as activity_category,

        -- flag gain vs dépense de miles
        case
            when lower(activity_type::varchar) like '%utilisé%'
            or lower(activity_type::varchar) like '%dépensé%'
            or lower(activity_type::varchar) like '%expiré%'
            then false else true
        end                                                         as is_earn,

        -- flag miles gagnés sur vol (cœur du programme)
        case
            when lower(activity_type::varchar) like '%vol%'
            and lower(activity_type::varchar) like '%gagn%'
            then true else false
        end                                                         as is_flight_earn,

        -- flag miles achetés (signal engagement fort)
        case
            when lower(activity_type::varchar) like '%achet%'
            then true else false
        end                                                         as is_purchased_miles,

        -- flag miles partenaire (diversification programme)
        case
            when lower(activity_type::varchar) like '%partenaire%'
            or lower(activity_type::varchar) like '%hôtel%'
            then true else false
        end                                                         as is_partner_earn,

        -- flag miles bonus (coût marketing pour l'airline)
        case
            when lower(activity_type::varchar) like '%bonus%'
            or lower(activity_type::varchar) like '%promotion%'
            then true else false
        end                                                         as is_bonus_miles,

        -- volume de miles
        case
            when miles_amount::integer >= 3000  then 'high'
            when miles_amount::integer >= 1000  then 'medium'
            else                                     'low'
        end                                                         as miles_volume_category,

        -- window functions par customer
        -- total miles cumulés du client
        sum(miles_amount::integer) over (
            partition by customer_id
        )                                                           as customer_total_miles,

        -- valeur totale estimée du client
        round(sum(estimated_value_usd::double) over (
            partition by customer_id
        ), 2)                                                       as customer_total_value_usd,

        -- nombre d'activités du client
        count(*) over (
            partition by customer_id
        )                                                           as customer_activity_count,

        -- miles gagnés sur vol uniquement par client
        sum(case
            when lower(activity_type::varchar) like '%vol%'
            and lower(activity_type::varchar) like '%gagn%'
            then miles_amount::integer else 0
        end) over (
            partition by customer_id
        )                                                           as customer_flight_miles_total,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when activity_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when customer_id is null
            then true else false
        end                                                         as is_fk_missing,

        case
            when miles_amount::integer <= 0
            then true else false
        end                                                         as is_miles_invalid,

        case
            when estimated_value_usd::double < 0
            then true else false
        end                                                         as is_value_invalid,

        -- miles > 100 000 sur une seule transaction = suspect
        case
            when miles_amount::integer > 100000
            then true else false
        end                                                         as is_miles_suspect,

        -- valeur par mile hors norme
        -- standard industrie = 0.01 à 0.02 USD par mile
        case
            when (estimated_value_usd::double / nullif(miles_amount::integer, 0))
                not between 0.001 and 0.10
            then true else false
        end                                                         as is_value_per_mile_suspect

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_fk_missing = false
)

select * from final