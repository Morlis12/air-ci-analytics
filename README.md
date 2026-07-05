# Air CI Project — Analytics Engineering Challenge

## Overview

Complete end-to-end analytics pipeline for a commercial airline based
in Abidjan (Côte d'Ivoire). This project covers: data processing,
dimensional modeling, semantic layer definition, a formal OWL/RDF
ontology layer for semantic interoperability, an executive
decision-making dashboard in Power BI, and an AI interface powered
by the Model Context Protocol (MCP) connected to Claude Desktop.

---

## Architecture
Excel (Donn.xlsx)
↓
DuckDB (air_ci.db)              ← Local Data Warehouse
↓
dbt-fusion                      ← Data Transformation Layer
├── staging/                  ← 12 Data Cleaning Models
└── marts/                    ← 7 Analytical Models
├── dimensions/           ← dim_date, dim_routes, dim_customers
└── facts/                ← fct_flights, fct_bookings,
fct_tickets, mart_decision_layer
↓
OWL Ontology (NEW)              ← Formal Semantic Layer
├── owl/01_schema.py          ← Classes, properties, axioms
├── owl/02_export.py          ← DuckDB → RDF individuals
└── owl/03_classify.py        ← SPARQL CONSTRUCT → labels
↓
Power BI                        ← Executive Decision Dashboard (4 pages)
↓
MCP Server (Python)             ← AI Interface — 8 SQL tools + 3 OWL tools
↓
Claude Desktop                  ← Conversational AI Agent
---

## Prerequisites

- Python 3.10 or 3.11 (not 3.14 — incompatible with some dependencies)
- dbt-fusion 2.0+
- DuckDB 1.5+
- Power BI Desktop (Windows)
- Claude Desktop (https://claude.ai/download)

---

## Installation

### 1. Clone or download the project folder

```powershell
cd "Air Ci Project"
```

### 2. Create the Python virtual environment

```powershell
python -m venv superset-env
.\superset-env\Scripts\Activate.ps1
python -m pip install duckdb mcp numpy pandas rdflib owlrl
```

> `rdflib` and `owlrl` are required for the OWL ontology layer.

### 3. Configure dbt profiles

Create `~/.dbt/profiles.yml` (never commit to Git):

```yaml
air_ci_profile:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: 'C:\Users\<your_name>\...\Air Ci Project\air_ci.db'
      extensions:
        - spatial
```

### 4. Run the dbt pipeline

```powershell
dbt run
```

Expected output: 35 total | 35 success

### 5. Run the OWL ontology pipeline (NEW)

Run once to build the schema, then after every `dbt run`:

```powershell
python owl\01_schema.py    # run once (or when rules change)
python owl\02_export.py    # run after every dbt run
python owl\03_classify.py  # run after every dbt run
```

Expected: `owl/air_ci_classified.ttl` generated with route
and customer OWL labels inferred by SPARQL CONSTRUCT rules.

### 6. Connect Claude Desktop (MCP Setup)

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "air-ci-analytics": {
      "command": "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project\\superset-env\\Scripts\\python.exe",
      "args": [
        "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project\\mcp_server.py"
      ],
      "cwd": "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project"
    }
  }
}
```

Restart Claude Desktop. Verify: Settings → Developer →
air-ci-analytics → status: running.

### 7. Open the Dashboard

Launch Power BI Desktop → File → Open → air_ci_dashboard.pbix

### 8. Verify the MCP tools

```powershell
python test_mcp.py
```

All 5 tests should pass.

---

## Project Structure
Air Ci Project/
├── models/
│   ├── staging/              ← 12 data cleaning stg_*.sql files
│   └── marts/
│       ├── dimensions/       ← dim_date, dim_routes, dim_customers
│       └── facts/            ← fct_flights, fct_bookings,
│                                fct_tickets, mart_decision_layer
├── macros/
│   └── load_spatial.sql
├── owl/                      ← NEW — OWL ontology layer
│   ├── 01_schema.py          ← OWL classes, properties, axioms
│   ├── 02_export.py          ← DuckDB marts → RDF individuals
│   ├── 03_classify.py        ← SPARQL CONSTRUCT rules → labels
│   └── air_ci_schema.ttl     ← Generated schema (versioned)
├── mcp_server.py             ← MCP Server — 8 SQL + 3 OWL tools
├── test_mcp.py               ← Test script for MCP tools
├── dbt_project.yml           ← dbt core configuration
├── air_ci.db                 ← DuckDB file warehouse
├── Donn.xlsx                 ← Source raw Excel data
├── requirements.txt
├── README.md
├── DATA_DICTIONARY.md
└── WRITE_UP.md
---

## Daily workflow

After any data update, run in this order:

```powershell
dbt run
python owl\02_export.py
python owl\03_classify.py
```

---

## Useful Commands

```powershell
# Run the full dbt transformation pipeline
dbt run

# Run data quality tests
dbt test

# List all models in the project
dbt list

# Run the OWL ontology pipeline
python owl\01_schema.py
python owl\02_export.py
python owl\03_classify.py

# Test all MCP tools locally
python test_mcp.py

# Run the MCP Server (Claude Desktop connects automatically)
python mcp_server.py
```

---

## Acceptance Criteria

| Question | MCP Tool | Underlying Model |
|---|---|---|
| Routes for Q4 budget scaling? | get_routes_budget_recommendation() | mart_decision_layer |
| Operationally unprofitable routes? | get_route_performance() | fct_flights |
| At-risk high-value customers? | get_high_value_at_risk_customers() | mart_decision_layer |
| Customer segments for premium upgrades? | get_upsell_segments() | mart_decision_layer |
| Side-by-side route comparison? | compare_routes() | fct_flights + fct_tickets |
| Root-cause evidence for suggestions? | get_unstructured_insights() | fct_tickets |
| Why is R009 GrowthOpportunity? (NEW) | explain_why_classified('R009') | air_ci_classified.ttl |
| OWL customer classification? (NEW) | get_owl_customer_classification() | air_ci_classified.ttl |

---

## MCP Server tools

### SQL tools — read from DuckDB (air_ci.db)

| Tool | Description |
|---|---|
| get_global_kpis() | High-level executive airline dashboard view |
| get_route_performance(route_id?) | Financial and operational tracking per route |
| get_routes_budget_recommendation() | Q4 scaling vs restructuring paths |
| get_complaints_by_route(route_id?) | NLP-driven sentiment and complaint summaries |
| compare_routes(route_id_1, route_id_2) | Side-by-side performance audit for two routes |
| get_high_value_at_risk_customers(limit?) | Churn mitigation list |
| get_upsell_segments() | High-probability targets for premium campaigns |
| get_unstructured_insights(category?) | Deeper parsing of customer review logs |

### OWL tools — read from air_ci_classified.ttl (NEW)

| Tool | Description |
|---|---|
| get_owl_route_classification() | OWL-inferred labels for all routes |
| get_owl_customer_classification(label?) | OWL-inferred labels — all or filtered |
| explain_why_classified(entity_id, type) | Full reasoning trace behind a classification |

---

## MCP Communication Topology
Claude Desktop
↓ MCP Protocol (stdio)
mcp_server.py (Python)
↓
┌───────────────────────────────┐
│  SQL tools → DuckDB           │  ← marts dbt (structured data)
│  OWL tools → air_ci_classified│  ← graphe RDF (inferred labels)
│              .ttl (rdflib)    │
└───────────────────────────────┘
---

## OWL Ontology layer (NEW)

The OWL layer adds semantic interoperability on top of the dbt marts.
It expresses the same classification logic as mart_decision_layer
(SQL CASE WHEN) as formal SPARQL CONSTRUCT rules on an RDF graph.

**Key benefits over SQL labels:**
- `owl:sameAs` federation with external systems (IATA, ECOWAS)
  without ETL — no data copying
- Logical consistency checking via `disjointWith` axioms
- Full reasoning trace: `explain_why_classified()` exposes exactly
  which metrics triggered which label

**Add to .gitignore:**
owl/air_ci_data.ttl
owl/air_ci_classified.ttl
---

## Unstructured Data Specifications

The MCP Server exposes text mining metrics as structured fields:

| Field | Type | Description |
|---|---|---|
| sentiment_score | DECIMAL -1 to +1 | Pre-calculated NLP score |
| primary_complaint_category | VARCHAR | delay / baggage / refund / cancellation... |
| urgency_level | VARCHAR | critical / high / medium / low |
| is_high_value_critical_ticket | BOOLEAN | Priority alert — immediate escalation |

---

## Demo Prompts for Claude Desktop
"Which routes should receive more budget next quarter?"
"Which customers are high value and at risk of churn?"
"What complaints are driving low satisfaction on route R009?"
"Compare routes R001 and R009 using financial and satisfaction signals."
"Which customer segments should receive premium upgrade offers?"
"Why is route R009 classified as GrowthOpportunity?"
"Show me the OWL classification of HighValueAtRisk customers."
"Explain why customer CUST001 received the HighValueAtRisk label."

