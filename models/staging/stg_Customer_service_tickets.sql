-- models/staging/stg_Customer_service_tickets.sql
with source as (
    select * from {{ source('excel_source', 'Customer_service_tickets') }}
),

cleaned as (
    select
        ticket_id::varchar                                          as raw_ticket_id,
        customer_id::varchar                                        as raw_customer_id,
        flight_id::varchar                                          as raw_flight_id,
        ticket_category::varchar                                    as raw_ticket_category,
        customer_comments::varchar                                  as raw_customer_comments,
        sentiment_score::double                                     as sentiment_score,
        resolution_status::varchar                                  as raw_resolution_status,
        resolution_time_days::integer                               as resolution_time_days
    from source
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(raw_ticket_id), '')                             as ticket_id,
        nullif(trim(raw_customer_id), '')                           as customer_id,
        nullif(trim(raw_flight_id), '')                             as flight_id,

        -- =========================================
        -- CATÉGORIE & COMMENTAIRES
        -- =========================================
        nullif(trim(raw_ticket_category), '')                       as ticket_category,
        nullif(trim(raw_customer_comments), '')                     as customer_comments,

        -- =========================================
        -- SENTIMENT & RÉSOLUTION
        -- =========================================
        sentiment_score,
        nullif(trim(raw_resolution_status), '')                     as resolution_status,
        resolution_time_days,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================
        case
            when sentiment_score >= 0.5   then 'positive'
            when sentiment_score >= 0.0   then 'neutral'
            when sentiment_score >= -0.5  then 'negative'
            else                               'very_negative'
        end                                                         as sentiment_label,

        case
            when sentiment_score < -0.7
            and lower(raw_resolution_status) != 'résolu'
            then 'critical'
            when sentiment_score < -0.5
            and lower(raw_resolution_status) != 'résolu'
            then 'high'
            when sentiment_score < 0
            and lower(raw_resolution_status) != 'résolu'
            then 'medium'
            else 'low'
        end                                                         as urgency_level,

        case
            when lower(raw_resolution_status) = 'résolu'
            then true else false
        end                                                         as is_resolved,

        case
            when lower(raw_resolution_status) = 'ouvert'
            then true else false
        end                                                         as is_open,

        case
            when lower(raw_resolution_status) = 'en cours'
            then true else false
        end                                                         as is_in_progress,

        case
            when resolution_time_days > 3
            and lower(raw_resolution_status) = 'résolu'
            then true else false
        end                                                         as is_sla_breached,

        case
            when lower(raw_ticket_category) like '%retard%'
            then true else false
        end                                                         as is_delay_related,

        case
            when lower(raw_ticket_category) like '%annulation%'
            then true else false
        end                                                         as is_cancellation_related,

        case
            when lower(raw_customer_comments) like '%bloqué%'
            or lower(raw_customer_comments) like '%compensation%'
            or lower(raw_customer_comments) like '%correspondance%'
            or lower(raw_customer_comments) like '%remboursement%'
            then true else false
        end                                                         as has_critical_keywords,

        -- =========================================
        -- FLAGS QUALITÉ — sur colonnes RAW
        -- =========================================
        case
            when trim(raw_ticket_id) = '' or raw_ticket_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when trim(raw_customer_id) = '' or raw_customer_id is null
            or trim(raw_flight_id) = '' or raw_flight_id is null
            then true else false
        end                                                         as is_fk_missing,

        case
            when sentiment_score not between -1 and 1
            then true else false
        end                                                         as is_sentiment_invalid,

        case
            when resolution_time_days < 0
            then true else false
        end                                                         as is_resolution_time_invalid,

        case
            when raw_customer_comments is null
            or trim(raw_customer_comments) = ''
            then true else false
        end                                                         as is_comment_empty

    from cleaned
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_fk_missing = false
)

select * from final