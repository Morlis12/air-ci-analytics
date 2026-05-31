# Air CI Project — Analytics Engineering Challenge

## Overview

Complete end-to-end analytics pipeline for a commercial airline based in Abidjan (Côte d'Ivoire).
This project covers: data processing, dimensional modeling, semantic layer definition, 
an executive decision-making dashboard, and an AI interface powered by the Model Context Protocol (MCP).

---

## Architecture
Excel (Donn.xlsx)
↓
DuckDB (air_ci.db)         ← Local Data Warehouse
↓
dbt-fusion                 ← Data Transformation Layer
├── staging/             ← 12 Data Cleaning Models
└── marts/               ← 7 Analytical Models
    ├── dimensions/      ← dim_date, dim_routes, dim_customers
    └── facts/           ← fct_flights, fct_bookings, fct_tickets, mart_decision_layer
↓
Power BI                   ← Executive Decision Dashboard (4 pages)
↓
MCP Server (Python)        ← Autonomous AI Interface with 8 Tools

---

## Prerequisites

- Python 3.10+
- dbt-fusion 2.0+
- DuckDB 1.5+
- Power BI Desktop (Windows)

---

## Installation

### 1. Clone or download the project folder

```bash
cd "Air Ci Project"
```

### 2. Create the Python virtual environment

```powershell
python -m venv superset-env
.\superset-env\Scripts\Activate.ps1
python -m pip install duckdb mcp numpy pandas
```

### 3. Configure DuckDB — Initialize Excel source views

```powershell
.\duckdb.exe air_ci.db
```

Inside the DuckDB CLI console:
```sql
INSTALL spatial;
LOAD spatial;
CREATE SCHEMA IF NOT EXISTS excel_source;

CREATE OR REPLACE VIEW excel_source.Flights AS
SELECT * FROM st_read('Donn.xlsx', layer='Flights');

-- (repeat this step for all 12 source tables)
.quit
```

### 4. Run the dbt pipeline

```powershell
dbt run
```

Expected output:
35 total | 35 success

### 5. Launch the MCP Server

```powershell
python mcp_server.py
```

### 6. Open the Dashboard
Launch Power BI Desktop
→ File → Open → air_ci_dashboard.pbix

---

## Project Structure
Air Ci Project/
├── models/
│   ├── staging/           ← 12 data cleaning stg_*.sql files
│   └── marts/
│       ├── dimensions/    ← dim_date, dim_routes, dim_customers
│       └── facts/         ← fct_flights, fct_bookings,
│                             fct_tickets, mart_decision_layer
├── macros/
│   └── load_spatial.sql
├── mcp_server.py          ← MCP Server backend (8 AI tools)
├── test_mcp.py            ← Test script for MCP tools
├── dbt_project.yml        ← dbt core configuration
├── air_ci.db              ← DuckDB file warehouse
├── Donn.xlsx              ← Source raw Excel data
├── README.md
├── DATA_DICTIONARY.md
└── WRITE_UP.md

---

## Useful Commands

```powershell
# Run the entire transformation pipeline
dbt run

# Run data quality tests
dbt test

# List all detected models in the project
dbt list

# Test the MCP Server tools locally
python test_mcp.py

# Run the live MCP Server
python mcp_server.py
```

---

## Covered Acceptance Criteria


| Criteria / Question | MCP Tool | Underlying Mart |
|---|---|---|
| Routes for Q4 budget scaling? | get_routes_budget_recommendation | mart_decision_layer |
| Operationally unprofitable routes? | get_route_performance | fct_flights |
| At-risk high-value customers? | get_high_value_at_risk_customers | mart_decision_layer |
| Customer segments for premium upgrades? | get_upsell_segments | mart_decision_layer |
| Side-by-side route comparison? | compare_routes | fct_flights + fct_tickets |
| Root-cause evidence for suggestions? | get_unstructured_insights | fct_tickets |

## Claude Desktop Connection (MCP Setup)

### Prerequisites
- Claude Desktop application installed (https://claude.ai/download)

### Configuration Setup
1. Open the Claude Desktop configuration file path:
   %APPDATA%\Claude\claude_desktop_config.json

2. Replace the contents with the following configuration snippet (make sure to adjust the absolute file paths to match your local hosting path):
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

3. Restart your Claude Desktop application.
4. Verify the handshake: Go to Settings → Developer → air-ci-analytics should display a running status.

### Live Demo Prompts
- "Which routes should receive more budget next quarter?"
- "Which customers are high value and at risk of churn?"
- "What complaints are driving low satisfaction on route R009?"
- "Compare routes R001 and R009 using financial and satisfaction signals."
- "Which customer segments should receive premium upgrade offers?"

### MCP Communication Topology
Claude Desktop
↓ MCP Protocol
mcp_server.py (Python Passerelle)
↓ Live SQL Queries
DuckDB (air_ci.db File)
↓
Structured dbt Marts + Unstructured NLP Customer Service Tickets

### The 8 Exposed AI Tools
1. get_global_kpis            → High-level executive airline dashboard view
2. get_route_performance      → Financial and operational tracking per route
3. get_routes_budget_recommendation → Q4 scaling vs restructuring paths
4. get_complaints_by_route    → NLP-driven sentiment and review summaries
5. compare_routes             → Side-by-side performance audit for two distinct routes
6. get_high_value_at_risk_customers → Churn mitigation list
7. get_upsell_segments        → High-probability targets for premium campaigns
8. get_unstructured_insights  → Deeper parsing of text review logs

### Unstructured Data Specifications
The MCP Server converts text mining metrics into rich contextual fields for the AI Agent:
- sentiment_score: Continuous variable bounded between -1 and +1
- primary_complaint_category: Categorical flags mapping delay, baggage, refund...
- urgency_level: Prioritization sorting: critical, high, medium, low
- is_high_value_critical_ticket: High-priority alert identifier forcing instant escalation
