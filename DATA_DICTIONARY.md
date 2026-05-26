# Data Dictionary — Air CI Project

## Sources (Excel — Donn.xlsx)

| Table | Description | Nb colonnes |
|---|---|---|
| Flights | Vols opérés | 12 |
| Airports | Référentiel aéroports | 7 |
| Routes | Routes aériennes | 6 |
| Customers | Profil clients | 11 |
| Bookings | Réservations | 12 |
| Flight_costs | Coûts par vol | 6 |
| Customer_service_tickets | Réclamations clients | 8 |
| Ancillary_details | Achats additionnels | 5 |
| Competitor_context | Données concurrentielles | 5 |
| Weather_impact | Impact météo | 6 |
| Cargo_operations | Opérations cargo | 6 |
| Loyalty_activity | Programme fidélité | 5 |

---

## Staging Models

### stg_flights
| Colonne | Type | Description |
|---|---|---|
| flight_id | varchar | Identifiant unique du vol |
| flight_number | varchar | Numéro de vol (ex: HF101) |
| route_id | varchar | Référence vers la route |
| flight_date | date | Date du vol |
| scheduled_departure_at | timestamp | Départ prévu |
| actual_departure_at | timestamp | Départ réel |
| seat_capacity | integer | Capacité en sièges |
| delay_minutes | integer | Retard en minutes |
| is_delayed | boolean | Vol retardé >= 15 min |
| is_cancelled | boolean | Vol annulé |
| flight_cost_key | varchar | Clé composite flight_id+route_id+date |

### stg_customers
| Colonne | Type | Description |
|---|---|---|
| customer_id | varchar | Identifiant unique client |
| customer_segment | varchar | standard/budget/business |
| loyalty_tier | varchar | None/Explorer/Gold/Platinum |
| age_years | integer | Âge calculé dynamiquement |
| generation | varchar | Baby Boomer/Gen X/Millennial/Gen Z |
| is_loyalty_member | boolean | Membre programme fidélité |
| is_domestic_customer | boolean | Client basé en Côte d'Ivoire |

### stg_customer_service_tickets
| Colonne | Type | Description |
|---|---|---|
| ticket_id | varchar | Identifiant unique ticket |
| sentiment_score | double | Score NLP : -1 (négatif) à +1 (positif) |
| sentiment_label | varchar | very_negative/negative/neutral/positive |
| urgency_level | varchar | critical/high/medium/low |
| has_delay_keyword | boolean | Mention retard dans commentaire |
| has_baggage_keyword | boolean | Mention bagage dans commentaire |
| has_refund_keyword | boolean | Mention remboursement |
| is_sla_breached | boolean | Résolution > 3 jours |

---

## Mart Models

### fct_flights
| Colonne | Type | Description |
|---|---|---|
| flight_id | varchar | Clé primaire |
| route_id | varchar | Clé étrangère → dim_routes |
| date_id | integer | Clé étrangère → dim_date |
| load_factor_pct | double | Taux remplissage (bookings/capacity*100) |
| total_revenue_usd | double | Ticket + ancillaire + cargo |
| total_cost_usd | double | Somme tous les coûts |
| flight_margin_usd | double | Revenue - Costs |
| flight_margin_pct | double | (Revenue-Costs)/Costs*100 |
| yield_usd_per_km | double | Revenue/distance/passagers |
| rask | double | Revenue/siège/km |
| cask | double | Coût/siège/km |
| is_operational_delay | boolean | Retard non météo |
| is_weather_driven_delay | boolean | Retard causé météo > 50% |
| is_profitable | boolean | Revenue > Costs |

### dim_customers
| Colonne | Type | Description |
|---|---|---|
| customer_id | varchar | Clé primaire |
| customer_segment | varchar | Segment commercial |
| loyalty_tier | varchar | Niveau fidélité |
| total_miles | integer | Miles cumulés |
| avg_sentiment_score | double | Sentiment moyen tickets |
| customer_value_score | double | Score CLV proxy |
| is_high_value | boolean | Client haute valeur |
| is_at_risk | boolean | Client à risque churn |
| is_upsell_candidate | boolean | Candidat upgrade |

### mart_decision_layer
| Colonne | Type | Description |
|---|---|---|
| decision_entity_type | varchar | "route" ou "customer" |
| entity_id | varchar | ID route ou client |
| entity_label | varchar | Nom lisible |
| ontology_label | varchar | Classification métier |
| recommendation | varchar | Action recommandée |
| metric_1 | double | KPI principal (load factor / revenue) |
| metric_2 | double | KPI secondaire (margin / ancillary rate) |
| metric_3 | double | KPI tertiaire (delay rate / days inactive) |
| metric_4 | double | Sentiment score |
| metric_5 | double | Revenue total / total miles |

---

## KPIs — Semantic Layer

| KPI | Formule | Seuil |
|---|---|---|
| load_factor | bookings/capacity*100 | < 60% = sous-rempli |
| route_margin | revenue - costs | < 0 = en perte |
| yield | ticket_rev/km/pax | Standard industrie |
| delay_rate | delayed/total*100 | > 20% = problème |
| cancellation_rate | cancelled/total*100 | > 5% = critique |
| ancillary_attach_rate | ancillary_rev/total_rev | Objectif 20-30% |
| rask | revenue/seat/km | Doit > cask |
| cask | cost/seat/km | Doit < rask |
| customer_sentiment | avg(sentiment_score) | > 0 = satisfait |

---

## Labels Ontologiques

### Routes
| Label | Critères | Action |
|---|---|---|
| 🟢 GrowthOpportunity | LF>=80%, margin>=15%, concurrents<=1 | Augmenter fréquence |
| 🔴 StrategicUnderperformer | Route stratégique + margin<10% ou delay>30% | Audit urgent |
| 🟠 OperationallyUnprofitable | Margin<0% + LF>=65% + délais opérationnels | Revoir coûts |
| ⚪ DemandUnprofitable | Margin<0% + LF<65% | Évaluer suspension |
| 🔵 RouteToDefend | Margin>=10% + concurrents>=3 | Améliorer satisfaction |
| 🟡 StableRoute | Équilibré | Maintenir |

### Clients
| Label | Critères | Action |
|---|---|---|
| 🔴 HighValueAtRisk | High value + sentiment<-0.3 ou inactif>90j | Contact prioritaire |
| 🟢 LoyaltyConversionTarget | Non membre + bookings>=2 + revenue>=300 | Proposer fidélité |
| 🔵 PremiumUpgradeCandidate | Standard + miles>=5000 + ancillary>=50% | Offrir upgrade |
| 🟡 AncillaryOfferTarget | Bookings>=2 + ancillary<30% | Campagne ciblée |
| ⚪ ReactivationTarget | Inactif > 180 jours | Email réactivation |
| ✅ StableCustomer | Équilibré | Maintenir engagement |