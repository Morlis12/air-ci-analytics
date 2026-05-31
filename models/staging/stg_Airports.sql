-- models/staging/stg_airports.sql
with source as (
    -- dbt va automatiquement lire l'onglet 'Airports' dans Donn.xlsx
    select * from {{ source('excel_source', 'Airports') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(airport_code::varchar), '')             as airport_code,
        nullif(trim(airport_name::varchar), '')             as airport_name,

        -- =========================================
        -- LOCALISATION
        -- =========================================
        nullif(trim(city::varchar), '')                     as city,
        nullif(trim(country::varchar), '')                  as country,
        nullif(trim(timezone::varchar), '')                 as timezone,

        -- =========================================
        -- COORDONNÉES
        -- =========================================
        latitude::double                                    as latitude,
        longitude::double                                   as longitude,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- continent déduit depuis le timezone
        case
            when timezone::varchar like 'Africa/%'  then 'Africa'
            when timezone::varchar like 'Europe/%'  then 'Europe'
            when timezone::varchar like 'America/%' then 'America'
            when timezone::varchar like 'Asia/%'    then 'Asia'
            else 'Unknown'
        end                                                 as continent,

        -- un aéroport hors Côte d'Ivoire est forcément international
        -- pour une airline basée à ABJ
        case
            when country::varchar != 'Côte d''Ivoire' then true
            when lower(airport_name::varchar) like '%international%' then true
            else false
        end                                                 as is_international,

        -- flag hub domestique Côte d'Ivoire
        case
            when country::varchar = 'Côte d''Ivoire'
            then true else false
        end                                                 as is_domestic,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when airport_code is null
            then true else false
        end                                                 as is_id_missing,

        case
            when latitude::double not between -90 and 90
            then true else false
        end                                                 as is_latitude_invalid,

        case
            when longitude::double not between -180 and 180
            then true else false
        end                                                 as is_longitude_invalid

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
)

select * from final