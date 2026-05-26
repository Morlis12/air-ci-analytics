-- models/staging/stg_weather_impact.sql
with source as (
    select * from {{ source('excel_source', 'Weather_impact') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(weather_id::varchar), '')                       as weather_id,
        nullif(trim(airport_code::varchar), '')                     as airport_code,
        date::date                                                  as weather_date,

        -- =========================================
        -- SAISON & RISQUE
        -- =========================================
        nullif(trim(season_type::varchar), '')                      as season_type,
        nullif(trim(disruption_risk_level::varchar), '')            as disruption_risk_level,
        average_delay_caused_min::integer                           as average_delay_caused_min,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- normalisation du niveau de risque en score numérique
        -- pour faciliter les tris et agrégations dans les marts
        case
            when lower(disruption_risk_level::varchar) = 'élevé'   then 3
            when lower(disruption_risk_level::varchar) = 'moyen'   then 2
            when lower(disruption_risk_level::varchar) = 'faible'  then 1
            else 0
        end                                                         as disruption_risk_score,

        -- catégorie saison normalisée en anglais
        -- (utile pour les dashboards multilingues)
        case
            when lower(season_type::varchar) like '%harmattan%'
            then 'harmattan'
            when lower(season_type::varchar) like '%petite saison sèche%'
            then 'short_dry_season'
            when lower(season_type::varchar) like '%grande saison sèche%'
            then 'long_dry_season'
            when lower(season_type::varchar) like '%petite saison des pluies%'
            then 'short_rainy_season'
            when lower(season_type::varchar) like '%grande saison des pluies%'
            then 'long_rainy_season'
            when lower(season_type::varchar) like '%saison sèche%'
            then 'dry_season'
            when lower(season_type::varchar) like '%saison des pluies%'
            then 'rainy_season'
            else 'unknown'
        end                                                         as season_type_normalized,

        -- flag météo perturbatrice
        case
            when lower(disruption_risk_level::varchar) in ('élevé', 'moyen')
            then true else false
        end                                                         as is_disruptive_weather,

        -- flag risque élevé uniquement
        case
            when lower(disruption_risk_level::varchar) = 'élevé'
            then true else false
        end                                                         as is_high_risk,

        -- flag délai météo significatif (>= 15 min = seuil IATA)
        case
            when average_delay_caused_min::integer >= 15
            then true else false
        end                                                         as is_significant_delay,

        -- catégorie de délai météo
        case
            when average_delay_caused_min::integer = 0      then 'no_delay'
            when average_delay_caused_min::integer < 15     then 'minor'
            when average_delay_caused_min::integer < 45     then 'moderate'
            else                                                  'severe'
        end                                                         as delay_category,

        -- mois et trimestre pour les analyses saisonnières
        month(date::date)                                           as weather_month,
        quarter(date::date)                                         as weather_quarter,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when weather_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when airport_code is null
            then true else false
        end                                                         as is_airport_missing,

        case
            when date is null
            then true else false
        end                                                         as is_date_missing,

        -- clé composite airport + date (un enregistrement par aéroport par jour)
        case
            when airport_code is null or date is null
            then true else false
        end                                                         as is_composite_key_incomplete,

        case
            when average_delay_caused_min::integer < 0
            then true else false
        end                                                         as is_delay_invalid,

        -- délai météo > 4h = suspect (240 min)
        case
            when average_delay_caused_min::integer > 240
            then true else false
        end                                                         as is_delay_suspect

    from source
),

final as (
    select * from renamed
    where is_id_missing = false
    and is_composite_key_incomplete = false
)

select * from final