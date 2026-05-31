# Write-Up — Air CI Analytics Engineering Challenge

## Executive Summary

This project delivers a full analytics engineering pipeline
for Air CI, a fictional airline based in Abidjan (ABJ),
Côte d'Ivoire. The pipeline covers data ingestion from
Excel, transformation via dbt, dimensional modeling,
a decision-oriented dashboard in Power BI, and an
agentic AI interface through a custom MCP Server
connected to Claude Desktop.

---

## 1. Assumptions

### Data
- Data covers fiscal year 2024–2025 for a fictional
  West African regional airline (hub: ABJ)
- 12 routes operated: 3 domestic, 8 regional, 1 international
  (ABJ–CDG)
- Sentiment scores in Customer_service_tickets are
  pre-calculated by an external NLP system and provided
  as-is in the source data (range: -1 to +1)
- Flight_costs table includes flight_date and route_id
  columns to form a composite key with flight_id,
  ensuring unambiguous cost attribution per flight
- All monetary values are expressed in USD for consistency

### Modeling
Star Schema was chosen over Data Vault because:
- DuckDB is optimized for star-schema analytical queries
- Simpler structure improves readability for the MCP Server
- Data volume (< 1M rows) does not require Data Vault
  auditability or historization overhead
- Power BI handles star schemas natively and efficiently

### Business thresholds
All thresholds are grounded in industry standards:

| Metric | Threshold | Source |
|---|---|---|
| Significant delay | >= 15 min | IATA standard |
| Low load factor | < 60% | Airline industry benchmark |
| High load factor | >= 85% | Airline industry benchmark |
| Ticket SLA | 3 days | Customer service standard |
| Inactive customer | > 180 days | CRM industry standard |
| At-risk customer | sentiment < -0.3 OR critical tickets >= 1 | Business rule |
| Ancillary attach rate target | 20–30% | Airline industry benchmark |

---

## 2. Architecture

### Pipeline overview
Excel (Donn.xlsx — 12 sheets)
↓  st_read() via DuckDB spatial extension
DuckDB (air_ci.db)
↓  on-run-start creates excel_source views
dbt-fusion pipeline
├── Layer 1: Staging (12 views)
│     → Cast, clean, nullif, trim
│     → Quality flags (is_id_missing, is_fk_missing)
│     → Business columns and NLP keyword detection
├── Layer 2: Marts — Dimensions (3 tables)
│     → dim_date, dim_routes, dim_customers
├── Layer 3: Marts — Facts (3 tables)
│     → fct_flights, fct_bookings, fct_tickets
├── Layer 4: Decision Layer (1 table)
│     → mart_decision_layer (ontology rules)
└── Layer 5: Semantic Layer (YAML)
→ 13 KPIs formally defined
↓
Exposition
├── Power BI (4-page dashboard via ODBC)
└── MCP Server (8 Python tools → Claude Desktop)

### Technology choices

| Component | Choice | Justification |
|---|---|---|
| Database | DuckDB | Reads Excel directly, no ETL needed, fast analytical queries |
| Transformation | dbt-fusion | SQL-based, testable, documented pipeline |
| Modeling | Star Schema | Simple, performant, readable for BI and AI tools |
| Dashboard | Power BI | Native Windows, ODBC connector, professional output |
| AI Interface | MCP Server + Claude Desktop | Open protocol, standard industry approach |

### Unstructured data integration

Customer comments are processed via a hybrid approach:

1. Pre-calculated sentiment score (-1 to +1) from source data
2. SQL keyword detection (10 complaint categories via LIKE patterns)
3. Cross-validation with operational data:
   is_delay_complaint_confirmed = ticket mentions delay
   AND flight was actually delayed

### Ontology layer

mart_decision_layer applies explicit business inference rules
classifying each route and customer into actionable categories:

Routes: GrowthOpportunity · StrategicUnderperformer ·
        OperationallyUnprofitable · DemandUnprofitable ·
        RouteToDefend · StableRoute

Customers: HighValueAtRisk · LoyaltyConversionTarget ·
           PremiumUpgradeCandidate · AncillaryOfferTarget ·
           ReactivationTarget · StableCustomer

Each entity receives an ontology label and a concrete
recommendation actionable by business teams.

---

## 3. Limitations

### Technical
- Python 3.14 is incompatible with Apache Superset
  → Power BI used as alternative dashboard tool
- dbt-fusion 2.0.0-preview has minor syntax differences
  from dbt-core standard
  → external_sources in profiles.yml not yet supported
  → workaround: on-run-start creates Excel views manually
- Semantic Layer cannot be fully validated locally
  → requires dbt Cloud for MetricFlow validation

### Data
- Average load factor of 16.77% is unusually low
  → likely due to partial booking data coverage
  → does not affect pipeline correctness
- Cargo data covers only 6 shipments across 3 flights
  → insufficient for route-level cargo optimization analysis
- No long historical data → seasonal trend analysis is limited
- Sentiment scores are pre-calculated externally
  → no custom French NLP model developed

### Modeling
- No SCD Type 2 implemented on dim_customers
  → customer segment changes are not historized
- No formal dbt tests (unique, not_null, relationships)
  → data quality relies on staging flags only
- Ontology rules are fixed thresholds
  → no ML model for dynamic churn prediction

---

## 4. Next Steps

### Short term (< 1 month)
- Add dbt tests: unique + not_null on all PKs,
  relationships on all FKs, accepted_values on statuses
- Implement SCD Type 2 on dim_customers
  to track segment and loyalty tier changes over time
- Enrich NLP with CamemBERT (French language model)
  for more accurate complaint classification

### Medium term (1–3 months)
- Replace static Excel with real-time APIs:
  weather data (OpenWeatherMap),
  competitor fares (Amadeus API)
- Build a churn prediction model using scikit-learn
  RandomForest on customer behavioral features
- Automate pipeline scheduling with Airflow or dbt Cloud

### Long term (3–6 months)
- Migrate from DuckDB local to Snowflake or BigQuery
  for multi-user access and production reliability
- Implement formal OWL/RDF ontology
  for automated reasoning beyond SQL rules
- Build an autonomous AI agent that generates
  weekly recommendations and distributes them
  to operational teams via Slack or email

---

## 5. Modeling Diagram

See DATA_DICTIONARY.md for the full column-level
documentation of each model.

The Star Schema diagram is available in:
screenshots/modeling_diagram.png
     dim_date
        │ date_id
        │
dim_routes ─┤            ┌── fct_bookings
route_id  └── fct_flights ── fct_tickets
│
mart_decision_layer
(routes + customers ontology)
│
dim_customers
customer_id

---

## 6. Acceptance Questions — Quick Reference

| Question | Model | MCP Tool |
|---|---|---|
| Routes to budget next quarter? | mart_decision_layer | get_routes_budget_recommendation() |
| Routes unprofitable operationally? | fct_flights | get_route_performance() |
| High-value customers at risk? | dim_customers | get_high_value_at_risk_customers() |
| Segments for premium offers? | mart_decision_layer | get_upsell_segments() |
| Compare two routes? | fct_flights + fct_tickets | compare_routes('R001','R009') |
| Evidence behind a recommendation? | fct_tickets | get_unstructured_insights() |