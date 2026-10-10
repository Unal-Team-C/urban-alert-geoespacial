#!/bin/bash
# Runs once, on an empty data volume (docker-entrypoint-initdb.d).
# Creates the test database and applies the schema to both; seed data only to the main one.
set -euo pipefail

SQL_DIR=/geospatial-db
TEST_DB=geospatial_test

run_psql() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" "$@"
}

run_psql --dbname "$POSTGRES_DB" -c "CREATE DATABASE ${TEST_DB}"

for db in "$POSTGRES_DB" "$TEST_DB"; do
    run_psql --dbname "$db" -f "$SQL_DIR/schema.sql"
done

if [ -f "$SQL_DIR/seed.sql" ]; then
    run_psql --dbname "$POSTGRES_DB" -f "$SQL_DIR/seed.sql"
fi
