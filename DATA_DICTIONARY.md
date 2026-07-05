# Data Dictionary — Air CI Project

---

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
| flight_id | varchar PK | Identifiant unique du vol — nullif/trim nettoyé |
| flight_number | varchar | Numéro de vol (ex: HF101) |
| route_id | varchar FK | Référence vers la route |
| flight_date | date | Date du vol |
| scheduled_departure_at | timestamp | Départ prévu |
| actual_departure_at | timestamp | Départ réel |
| seat_capacity | integer | Capacité en sièges |
| delay_minutes | integer | Retard en minutes |
| is_delayed | boolean | Vol retardé >= 15 min (standard IATA) |
| is_cancelled | boolean | Vol annulé |
| is_operational_delay | boolean | Retard non expliqué par la météo (opérationnel > 50%) |
| is_weather_driven_delay | boolean | Météo responsable de > 50% du retard |
| is_timeline_invalid | boolean | actual_arrival < actual_departure — flag qualité données |
| is_delay_suspect | boolean | delay_minutes > 1440 (> 24h — flag qualité) |
| is_speed_suspect | boolean | Vitesse calculée hors plage 300-1000 km/h |
| is_id_missing | boolean | Flag qualité — flight_id null |
| is_fk_missing | boolean | Flag qualité — route_id null |
| flight_cost_key | varchar | Clé composite flight_id + route_id + flight_date |

### stg_customers
| Colonne | Type | Description |
|---|---|---|
| customer_id | varchar PK | Identifiant unique client |
| customer_segment | varchar | standard / budget / business / premium |
| loyalty_tier | varchar | None / Silver / Gold / Platinum |
| age_years | integer | Âge calculé dynamiquement depuis birth_date |
| generation | varchar | Baby Boomer / Gen X / Millennial / Gen Z |
| is_loyalty_member | boolean | loyalty_tier NOT IN ('None', 'null', '') |
| is_domestic_customer | boolean | Client basé en Côte d'Ivoire |
| is_high_value | boolean | segment business/premium OU tier Gold/Platinum OU miles >= 10000 |
| is_at_risk | boolean | sentiment < -0.3 OU critical_tickets >= 1 OU inactif > 90j |
| is_upsell_candidate | boolean | Segment standard + miles >= 3000 + membre fidélité |
| is_minor | boolean | age < 18 |

### stg_customer_service_tickets
| Colonne | Type | Description |
|---|---|---|
| ticket_id | varchar PK | Identifiant unique ticket |
| sentiment_score | double | Score NLP : -1 (négatif) à +1 (positif) |
| sentiment_label | varchar | very_negative (<-0.5) / negative (<0) / neutral (>=0) / positive (>=0.5) |
| urgency_level | varchar | critical / high / medium / low |
| has_delay_keyword | boolean | NLP : 'retard', 'correspondance'... détecté |
| has_baggage_keyword | boolean | NLP : 'bagage', 'valise'... détecté |
| has_refund_keyword | boolean | NLP : 'remboursement'... détecté |
| has_cancellation_keyword | boolean | NLP : 'annulé', 'annulation'... détecté |
| has_overbooking_keyword | boolean | NLP : 'surréservation'... détecté |
| has_meal_keyword | boolean | NLP : 'repas'... détecté |
| has_seat_keyword | boolean | NLP : 'siège'... détecté |
| has_comfort_keyword | boolean | NLP : 'climatisation'... détecté |
| has_digital_keyword | boolean | NLP : 'application mobile'... détecté |
| has_staff_keyword | boolean | NLP : 'personnel'... détecté |
| primary_complaint_category | varchar | Catégorie principale déduite des 10 flags NLP |
| is_sla_breached | boolean | Résolution > 3 jours (SLA standard) |
| is_overdue_ticket | boolean | Non résolu ET résolution_time_days > 7 |
| is_delay_complaint_confirmed | boolean | has_delay_keyword = true ET vol effectivement retardé |

### stg_cargo_operations
| Colonne | Type | Description |
|---|---|---|
| cargo_id | varchar PK | Identifiant unique expédition |
| space_utilization_pct | decimal | (poids cargo / capacité max) * 100 |
| space_utilization_level | varchar | very_low (<20%) / low (<50%) / medium (<80%) / high (>=80%) |
| is_underutilized | boolean | space_utilization_pct < 20% |
| is_high_value_cargo | boolean | revenue_per_kg > 10 USD (fret express / pharma) |
| is_weight_suspect | boolean | cargo_weight_kg > 10000 — flag qualité données |

### stg_routes
| Colonne | Type | Description |
|---|---|---|
| route_id | varchar PK | Identifiant unique route |
| route_key | varchar | Paire codes IATA — ex: ABJ-CDG |
| distance_km | integer | Distance orthodromique |
| distance_category | varchar | short_haul (<500km) / medium_haul (<1500km) / long_haul |
| is_strategic_route | boolean | TRUE si internationale ou long-courrier |
| is_return_route | boolean | Origin != 'ABJ' — retour vers le hub |
| competitive_intensity | varchar | monopole / duopole / oligopole / haute_concurrence |
| is_speed_suspect | boolean | Vitesse calculée hors plage 300-1000 km/h |

---

## Mart Models

### fct_flights
| Colonne | Type | Description |
|---|---|---|
| flight_id | varchar PK | Clé primaire |
| route_id | varchar FK | Clé étrangère → dim_routes |
| date_id | integer FK | Clé étrangère → dim_date |
| seat_capacity | integer | Capacité totale en sièges |
| nb_bookings | integer | Réservations confirmées |
| load_factor_pct | double | (nb_bookings / seat_capacity) * 100 |
| total_revenue_usd | double | Ticket + ancillaire + cargo |
| total_cost_usd | double | Somme de tous les coûts opérationnels |
| flight_margin_usd | double | Revenue - Costs |
| flight_margin_pct | double | (Revenue - Costs) / Costs * 100 |
| yield_usd_per_km | double | ticket_revenue / distance_km / nb_passagers |
| rask | double | Revenue par siège disponible par km |
| cask | double | Coût par siège disponible par km |
| is_delayed | boolean | delay_minutes >= 15 |
| is_operational_delay | boolean | Retard non météo dominant |
| is_weather_driven_delay | boolean | Météo dominant dans le retard |
| is_profitable | boolean | total_revenue > total_cost |
| is_underloaded | boolean | load_factor_pct < 60% |
| is_high_load | boolean | load_factor_pct >= 85% |

### fct_bookings
| Colonne | Type | Description |
|---|---|---|
| booking_id | varchar PK | Clé primaire |
| flight_id | varchar FK | Clé étrangère → fct_flights |
| customer_id | varchar FK | Clé étrangère → dim_customers |
| date_id | integer FK | Clé étrangère → dim_date |
| ticket_price_usd | double | Prix du billet de base |
| ancillary_revenue_usd | double | Revenus services additionnels |
| total_revenue_usd | double | Ticket + ancillaire |
| ancillary_attach_level | varchar | none / low (1 item) / high (2+ items) |
| is_repeat_customer | boolean | total_past_bookings > 1 |
| days_since_last_booking | integer | Jours depuis la réservation précédente |
| is_inactive_customer | boolean | days_since_last_booking > 180 |

### fct_tickets
| Colonne | Type | Description |
|---|---|---|
| ticket_id | varchar PK | Clé primaire |
| flight_id | varchar FK | Clé étrangère → fct_flights |
| customer_id | varchar FK | Clé étrangère → dim_customers |
| sentiment_score | double | Score NLP -1 à +1 |
| sentiment_label | varchar | very_negative / negative / neutral / positive |
| urgency_level | varchar | critical / high / medium / low |
| primary_complaint_category | varchar | Catégorie principale (priorité : refund > baggage > delay...) |
| is_delay_complaint_confirmed | boolean | has_delay_keyword ET vol effectivement retardé |
| is_high_value_critical_ticket | boolean | is_high_value = true ET urgency IN ('critical','high') |
| is_sla_breached | boolean | resolution_time_days > 3 |
| is_overdue_ticket | boolean | Non résolu ET resolution_time_days > 7 |

### dim_routes
| Colonne | Type | Description |
|---|---|---|
| route_id | varchar PK | Clé primaire |
| route_key | varchar | Paire codes IATA — ex: ABJ-CDG |
| origin_airport_code | varchar | Code IATA départ |
| destination_airport_code | varchar | Code IATA arrivée |
| distance_km | integer | Distance orthodromique |
| distance_category | varchar | short_haul / medium_haul / long_haul |
| nb_competitors | integer | Compagnies concurrentes sur la route |
| competitive_intensity | varchar | monopole / duopole / oligopole / haute_concurrence |
| avg_competitor_fare_usd | double | Prix moyen concurrent — référence benchmarking |
| is_strategic_route | boolean | TRUE si internationale ou long-courrier |
| ontology_label | varchar | Label de classification SQL (mart_decision_layer) |
| recommendation | varchar | Recommandation actionnable associée |

### dim_customers
| Colonne | Type | Description |
|---|---|---|
| customer_id | varchar PK | Clé primaire |
| customer_segment | varchar | standard / business / premium |
| loyalty_tier | varchar | None / Silver / Gold / Platinum |
| age_years | integer | Âge du client |
| generation | varchar | Gen X / Millennial / Gen Z |
| total_miles | integer | Miles fidélité cumulés |
| avg_sentiment_score | double | Moyenne sentiment depuis fct_tickets |
| customer_value_score | double | loyalty_value_usd + (total_miles * 0.01) |
| loyalty_engagement_level | varchar | inactive / low / medium / high |
| is_high_value | boolean | segment premium OU tier Gold/Platinum OU miles >= 10000 |
| is_at_risk | boolean | sentiment < -0.3 OU critical_tickets >= 1 OU inactif > 90j |
| is_loyalty_member | boolean | loyalty_tier NOT IN ('None', 'null', '') |
| is_upsell_candidate | boolean | Standard + miles >= 3000 + membre fidélité |
| ontology_label | varchar | Label de classification SQL (mart_decision_layer) |
| recommendation | varchar | Recommandation actionnable associée |

### dim_date
| Colonne | Type | Description |
|---|---|---|
| date_id | integer PK | Format YYYYMMDD |
| full_date | date | Date calendaire |
| year / quarter / month | integer | Composantes temporelles |
| day_name | varchar | Lundi, Mardi... |
| is_weekend | boolean | Samedi ou Dimanche |
| season_demand | varchar | peak / shoulder / low |
| fiscal_quarter | varchar | Q1–Q4 calendrier fiscal Air CI |

### mart_decision_layer
| Colonne | Type | Description |
|---|---|---|
| decision_entity_type | varchar | 'route' ou 'customer' |
| entity_id | varchar | ID route ou client |
| entity_label | varchar | Nom lisible |
| ontology_label | varchar | Label de classification métier |
| recommendation | varchar | Action recommandée |
| metric_1 | double | KPI principal (load_factor / customer_value_score) |
| metric_2 | double | KPI secondaire (margin / ancillary_attach_rate) |
| metric_3 | double | KPI tertiaire (delay_rate / days_inactive) |
| metric_4 | double | Sentiment score |
| metric_5 | double | Revenue total / total miles |

---

## KPIs — Semantic Layer

13 KPIs définis dans `models/marts/semantic_layer.yml` (MetricFlow).
Nécessite dbt Cloud pour validation complète.

| KPI | Formule | Seuil / Source |
|---|---|---|
| load_factor | AVG(load_factor_pct) depuis fct_flights | < 60% = sous-rempli, > 85% = haut — IATA |
| route_margin | SUM(flight_margin_usd) depuis fct_flights | < 0 = en perte |
| route_margin_pct | AVG(flight_margin_pct) depuis fct_flights | Benchmark 10-20% |
| yield | AVG(yield_usd_per_km) depuis fct_flights | Standard industrie |
| delay_rate | SUM(is_delayed) / COUNT(*) depuis fct_flights | > 20% = problème |
| cancellation_rate | SUM(is_cancelled) / COUNT(*) depuis fct_flights | > 5% = critique |
| ancillary_attach_rate | SUM(has_ancillary) / COUNT(*) depuis fct_bookings | Objectif 20-30% |
| repeat_booking_rate | SUM(is_repeat) / COUNT(*) depuis fct_bookings | Fidélisation |
| customer_sentiment_score | AVG(sentiment_score) depuis fct_tickets | > 0 = satisfait |
| customer_lifetime_value | AVG(customer_value_score) depuis dim_customers | CLV proxy |
| rask | AVG(rask) depuis fct_flights | Doit > cask |
| cask | AVG(cask) depuis fct_flights | Doit < rask |
| loyalty_engagement_score | AVG basé sur tier et miles | Standard programme fidélité |

---

## Labels Ontologiques — SQL (mart_decision_layer)

### Routes (6 labels)

| Label | Critères SQL | Action recommandée |
|---|---|---|
| GrowthOpportunity | LF>=80% ET margin>=15% ET concurrents<=1 | Augmenter budget et fréquence |
| StrategicUnderperformer | is_strategic=true ET (margin<10% OU delay>30%) | Audit opérationnel urgent |
| OperationallyUnprofitable | margin<0% ET LF>=65% ET délais opérationnels dominants | Revoir structure de coûts |
| DemandUnprofitable | margin<0% ET LF<65% | Réduire fréquence ou suspendre |
| RouteToDefend | margin>=10% ET concurrents>=3 ET sentiment<-0.3 | Investissement qualité de service |
| StableRoute | Aucun signal particulier (défaut — ELSE) | Maintenir et monitorer |

### Clients (6 labels)

| Label | Critères SQL | Action recommandée |
|---|---|---|
| HighValueAtRisk | is_high_value=true ET (sentiment<-0.3 OU critical_tickets>=1 OU inactif>90j) | Contact prioritaire |
| LoyaltyConversionTarget | Non membre ET bookings>=2 ET revenue>=300 USD | Proposer programme fidélité |
| PremiumUpgradeCandidate | Segment standard ET miles>=5000 ET ancillary>=50% | Offrir upgrade premium |
| AncillaryOfferTarget | bookings>=2 ET ancillary<30% ET sentiment>=-0.2 | Campagne ancillaire ciblée |
| ReactivationTarget | inactif>180j ET bookings>=1 | Email de réactivation |
| StableCustomer | Aucun signal particulier (défaut — ELSE) | Maintenir l'engagement |

---

## OWL Ontology Layer (NOUVEAU)

Couche sémantique formelle générée à partir des marts dbt.
Exprime les mêmes règles de classification en logique OWL/RDF
pour l'interopérabilité avec des systèmes externes.

### Fichiers

| Fichier | Rôle | Sortie |
|---|---|---|
| owl/01_schema.py | Classes OWL, DatatypeProperty, ObjectProperty, disjointWith | air_ci_schema.ttl |
| owl/02_export.py | dim_routes + dim_customers → individus RDF via DuckDB | air_ci_data.ttl |
| owl/03_classify.py | Règles SPARQL CONSTRUCT → labels inférés | air_ci_classified.ttl |

### Classes OWL — Routes

| Classe OWL | Équivalent dbt | Règle SPARQL CONSTRUCT |
|---|---|---|
| air:GrowthOpportunity | Label mart_decision_layer | FILTER(?lf >= 80.0 && ?margin >= 15.0 && ?nc <= 1) |
| air:StrategicUnderperformer | Label mart_decision_layer | FILTER(is_strategic = true && (?margin < 10 \|\| ?delay > 30)) |
| air:OperationallyUnprofitable | Label mart_decision_layer | FILTER(?margin < 0.0 && ?lf >= 65.0) |
| air:DemandUnprofitable | Label mart_decision_layer | FILTER(?margin < 0.0 && ?lf < 65.0) |
| air:RouteToDefend | Label mart_decision_layer | FILTER(?margin >= 10.0 && ?nc >= 3 && ?sent < -0.3) |
| air:StableRoute | Défaut (ELSE) | FILTER NOT EXISTS sur tous les labels précédents |

### Classes OWL — Clients

| Classe OWL | Équivalent dbt | Règle SPARQL CONSTRUCT |
|---|---|---|
| air:HighValueAtRisk | Label mart_decision_layer | FILTER(isHighValue = true && (?sent < -0.3 \|\| ?crit >= 1 \|\| ?days > 90)) |
| air:LoyaltyConversionTarget | Label mart_decision_layer | FILTER(isLoyaltyMember = false && ?bookings >= 2 && ?rev >= 300) |
| air:PremiumUpgradeCandidate | Label mart_decision_layer | FILTER(?seg = 'standard' && ?miles >= 5000 && ?anc >= 50.0) |
| air:AncillaryOfferTarget | Label mart_decision_layer | FILTER(?bookings >= 2 && ?anc < 30.0 && ?sent >= -0.2) |
| air:ReactivationTarget | Label mart_decision_layer | FILTER(?days > 180 && ?bookings >= 1) |
| air:StableCustomer | Défaut (ELSE) | FILTER NOT EXISTS sur tous les labels précédents |

### DatatypeProperty — Routes

| Propriété | Type XSD | Colonne source | Utilisée dans |
|---|---|---|---|
| hasLoadFactorPct | xsd:decimal | AVG(fct_flights.load_factor_pct) | GrowthOpportunity, DemandUnprofitable |
| hasMarginPct | xsd:decimal | AVG(fct_flights.flight_margin_pct) | GrowthOpportunity, StrategicUnderperformer, DemandUnprofitable, RouteToDefend |
| hasNbCompetitors | xsd:integer | dim_routes.nb_competitors | GrowthOpportunity, RouteToDefend |
| hasDelayRatePct | xsd:decimal | SUM(is_delayed)/COUNT(*) | StrategicUnderperformer |
| isStrategicRoute | xsd:boolean | dim_routes.is_strategic_route | StrategicUnderperformer |
| hasAvgSentimentScore | xsd:decimal | AVG(fct_tickets.sentiment_score) | RouteToDefend |
| hasRouteKey | xsd:string | dim_routes.route_key | Affichage uniquement |

### DatatypeProperty — Clients

| Propriété | Type XSD | Colonne source | Utilisée dans |
|---|---|---|---|
| isHighValue | xsd:boolean | dim_customers.is_high_value | HighValueAtRisk |
| hasSentimentScore | xsd:decimal | dim_customers.avg_sentiment_score | HighValueAtRisk |
| hasCriticalTickets | xsd:integer | COUNT(urgency='critical') | HighValueAtRisk |
| hasDaysSinceLastFlight | xsd:integer | MAX(fct_bookings.days_since_last_booking) | HighValueAtRisk, ReactivationTarget |
| isLoyaltyMember | xsd:boolean | dim_customers.is_loyalty_member | LoyaltyConversionTarget |
| hasTotalBookings | xsd:integer | COUNT(fct_bookings) | LoyaltyConversionTarget, AncillaryOfferTarget, ReactivationTarget |
| hasTotalRevenue | xsd:decimal | SUM(fct_bookings.total_revenue_usd) | LoyaltyConversionTarget |
| hasCustomerSegment | xsd:string | dim_customers.customer_segment | PremiumUpgradeCandidate |
| hasTotalMiles | xsd:integer | dim_customers.total_miles | PremiumUpgradeCandidate |
| hasAncillaryAttachRate | xsd:decimal | SUM(has_ancillary)/COUNT(*) | PremiumUpgradeCandidate, AncillaryOfferTarget |
| hasCustomerKey | xsd:string | dim_customers.customer_id | Affichage uniquement |

### ObjectProperty

| Propriété | Domaine → Cible | Équivalent dbt | Utilité |
|---|---|---|---|
| hasOrigin | Route → Airport | origin_airport_code FK | Navigation : toutes les routes depuis ABJ |
| hasDestination | Route → Airport | destination_airport_code FK | Graphe réseau aérien |
| hasCompetitor | Route → Airline | stg_competitor_context | Analyse réseau concurrentiel |

### Outils MCP OWL

| Outil | Source | Répond à |
|---|---|---|
| get_owl_route_classification() | air_ci_classified.ttl | Labels OWL inférés pour toutes les routes |
| get_owl_customer_classification(label?) | air_ci_classified.ttl | Labels OWL inférés — tous ou filtrés par label |
| explain_why_classified(entity_id, type) | air_ci_classified.ttl | Trace complète du raisonnement : quelles métriques ont déclenché quel label |

### Stratégie Git — fichiers OWL

| Fichier | Committer ? | Raison |
|---|---|---|
| owl/01_schema.py | OUI | Code — change uniquement si les règles métier changent |
| owl/02_export.py | OUI | Code — change uniquement si la structure des marts change |
| owl/03_classify.py | OUI | Code — change uniquement si les règles de classification changent |
| owl/air_ci_schema.ttl | OUI | Schéma stable — le DDL de l'ontologie |
| owl/air_ci_data.ttl | NON — .gitignore | Régénéré après chaque dbt run |
| owl/air_ci_classified.ttl | NON — .gitignore | Régénéré après chaque dbt run + 03_classify.py |

### Interopérabilité — owl:sameAs

```turtle
# Fédérer avec un système externe sans ETL :
air:ABJ owl:sameAs ecowas:AbidjanFHB .
```

Une seule requête SPARQL peut récupérer notre classification de route
ET les données du système externe simultanément, sans copie de données.

---

## Référence KPIs métier

| KPI | Formule | Seuil | Source |
|---|---|---|---|
| Load Factor | (bookings / capacity) * 100 | <60% = sous-rempli, >85% = haut | IATA |
| RASK | ticket_revenue / (seats * km) | Doit > CASK | Standard airline |
| CASK | total_cost / (seats * km) | Doit < RASK | Standard airline |
| Yield | ticket_rev / km / nb_flown | Plus haut = meilleur revenu unitaire | Standard airline |
| CLV proxy | loyalty_value + (miles * 0.01) | 0.01 USD/mile | Standard |
| Délai significatif | >= 15 minutes | Seuil IATA | IATA |
| SLA ticket | > 3 jours résolution | Standard service client | Industrie |
| Client inactif | > 180 jours sans vol | Standard CRM | CRM |
| Client à risque | > 90 jours OU sentiment < -0.3 | Règle métier | Air CI |
| Ancillaire cible | 20-30% taux d'attachement | Ryanair ~30%, Air France ~20% | Benchmark |
| Cargo haute valeur | > 10 USD/kg | Fret express / pharma | Logistique aérienne |
| Utilisation cargo haute | >= 80% | Standard logistique | Logistique aérienne |