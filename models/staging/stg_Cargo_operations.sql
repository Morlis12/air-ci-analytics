-- models/staging/stg_Cargo_operations.sql
with source as (
    select * from {{ source('excel_source', 'Cargo_operations') }}
),

renamed as (
    select
        -- =========================================
        -- IDENTIFIANTS
        -- =========================================
        nullif(trim(cargo_shipment_id::varchar), '')                as cargo_shipment_id,
        nullif(trim(flight_id::varchar), '')                        as flight_id,

        -- =========================================
        -- CARACTÉRISTIQUES DU CARGO
        -- =========================================
        nullif(trim(cargo_type::varchar), '')                       as cargo_type,
        weight_kg::double                                           as weight_kg,
        cargo_revenue_usd::double                                   as cargo_revenue_usd,
        space_utilization_pct::double                               as space_utilization_pct,

        -- =========================================
        -- COLONNES CALCULÉES
        -- =========================================

        -- revenu par kg (rentabilité du cargo)
        case
            when weight_kg::double > 0
            then round(
                cargo_revenue_usd::double / weight_kg::double
            , 2)
            else null
        end                                                         as revenue_per_kg_usd,

        -- catégorie de cargo normalisée
        case
            when lower(cargo_type::varchar) like '%urgent%'
            or lower(cargo_type::varchar) like '%document%'
            then 'documents'
            when lower(cargo_type::varchar) like '%pharma%'
            then 'pharmaceutical'
            when lower(cargo_type::varchar) like '%périssable%'
            or lower(cargo_type::varchar) like '%perishable%'
            then 'perishable'
            when lower(cargo_type::varchar) like '%textile%'
            then 'textile'
            when lower(cargo_type::varchar) like '%électronique%'
            or lower(cargo_type::varchar) like '%electronic%'
            then 'electronics'
            else 'other'
        end                                                         as cargo_type_normalized,

        -- flag cargo haute valeur (revenu/kg élevé)
        case
            when (cargo_revenue_usd::double / nullif(weight_kg::double, 0)) > 10
            then true else false
        end                                                         as is_high_value_cargo,

        -- flag cargo sensible (pharma + périssable = contraintes logistiques)
        case
            when lower(cargo_type::varchar) like '%pharma%'
            or lower(cargo_type::varchar) like '%périssable%'
            then true else false
        end                                                         as is_sensitive_cargo,

        -- niveau d'utilisation de l'espace
        case
            when space_utilization_pct::double >= 80    then 'high'
            when space_utilization_pct::double >= 50    then 'medium'
            when space_utilization_pct::double >= 20    then 'low'
            else                                             'very_low'
        end                                                         as space_utilization_level,

        -- flag sous-utilisation (< 20% = espace gaspillé)
        case
            when space_utilization_pct::double < 20
            then true else false
        end                                                         as is_underutilized,

        -- flag sur-utilisation (> 95% = risque opérationnel)
        case
            when space_utilization_pct::double > 95
            then true else false
        end                                                         as is_overutilized,

        -- catégorie de poids
        case
            when weight_kg::double < 100    then 'light'
            when weight_kg::double < 500    then 'medium'
            when weight_kg::double < 1000   then 'heavy'
            else                                 'very_heavy'
        end                                                         as weight_category,

        -- =========================================
        -- FLAGS QUALITÉ
        -- =========================================
        case
            when cargo_shipment_id is null
            then true else false
        end                                                         as is_id_missing,

        case
            when flight_id is null
            then true else false
        end                                                         as is_fk_missing,

        case
            when weight_kg::double <= 0
            then true else false
        end                                                         as is_weight_invalid,

        case
            when cargo_revenue_usd::double <= 0
            then true else false
        end                                                         as is_revenue_invalid,

        case
            when space_utilization_pct::double < 0
            or space_utilization_pct::double > 100
            then true else false
        end                                                         as is_utilization_invalid,

        -- poids > 10 tonnes = suspect pour un vol régional
        case
            when weight_kg::double > 10000
            then true else false
        end                                                         as is_weight_suspect,

        -- revenu cargo > 50 000 USD = suspect
        case
            when cargo_revenue_usd::double > 50000
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