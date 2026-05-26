-- models/staging/stg_customers.sql
with source as (
    select * from {{ source('excel_source', 'Customers') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(customer_id::varchar), '')                      as customer_id,
        nullif(trim(first_name::varchar), '')                       as first_name,
        nullif(trim(last_name::varchar), '')                        as last_name,

        -- =========================================
        -- DÉMOGRAPHIE
        -- =========================================
        nullif(trim(upper(gender::varchar)), '')                    as gender,
        birth_date::date                                            as birth_date,
        nullif(trim(country::varchar), '')                          as country,
        nullif(trim(city::varchar), '')                             as city,

        -- =========================================
        -- SEGMENTATION & FIDÉLITÉ
        -- =========================================
        nullif(trim(lower(customer_segment::varchar)), '')          as customer_segment,

        -- normalisation loyalty_tier : 'None' → NULL
        case
            when trim(lower(loyalty_tier::varchar)) in ('none', 'null', '')
            then null
            else trim(loyalty_tier::varchar)
        end                                                         as loyalty_tier,

        nullif(trim(lower(preferred_channel::varchar)), '')         as preferred_channel,
        signup_date::date                                           as signup_date,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- âge calculé dynamiquement
        datediff(
            'year',
            birth_date::date,
            current_date
        )                                                           as age_years,

        -- génération déduite de l'année de naissance
        case
            when year(birth_date::date) < 1965  then 'Baby Boomer'
            when year(birth_date::date) < 1981  then 'Gen X'
            when year(birth_date::date) < 1997  then 'Millennial'
            when year(birth_date::date) < 2013  then 'Gen Z'
            else 'Unknown'
        end                                                         as generation,

        -- ancienneté client en jours
        datediff(
            'day',
            signup_date::date,
            current_date
        )                                                           as customer_tenure_days,

        -- flag client fidélisé (a un tier actif)
        case
            when trim(lower(loyalty_tier::varchar)) not in ('none', 'null', '')
            and loyalty_tier is not null
            then true else false
        end                                                         as is_loyalty_member,

        -- flag marché domestique
        case
            when country::varchar = 'Côte d''Ivoire'
            then true else false
        end                                                         as is_domestic_customer,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when customer_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when birth_date::date > current_date
            then true else false
        end                                                         as is_birthdate_future,

        case
            when datediff('year', birth_date::date, current_date) < 18
            then true else false
        end                                                         as is_minor,

        case
            when datediff('year', birth_date::date, current_date) > 100
            then true else false
        end                                                         as is_age_suspect,

        case
            when signup_date::date > current_date
            then true else false
        end                                                         as is_signup_future,

        case
            when signup_date::date < '2000-01-01'
            then true else false
        end                                                         as is_signup_suspect,

        case
            when upper(gender::varchar) not in ('M', 'F')
            then true else false
        end                                                         as is_gender_invalid

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
)

select * from final