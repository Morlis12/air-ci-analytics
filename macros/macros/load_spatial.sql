-- macros/load_spatial.sql
{% macro load_spatial() %}
    {% do run_query("LOAD spatial") %}
{% endmacro %}