#!/bin/sh
# Rebuilds the database, runs every query, exports results/, and verifies them with pandas.
# Usage (from the project root):  sh run_all.sh   [database name, default: retail]
set -e
DB="${1:-retail}"
createdb "$DB" 2>/dev/null || true
psql -d "$DB" -q -f sql/01_schema.sql 2>/dev/null
psql -d "$DB" -q -f sql/02_load.sql
mkdir -p results
for f in sql/queries/q*.sql; do
  name=$(basename "$f" .sql)
  psql -d "$DB" --csv -f "$f" -o "results/$name.csv"
  echo "ran $name"
done
psql -d "$DB" --csv -f sql/03_reconciliation.sql -o results/reconciliation.csv
python verification/verify_with_pandas.py
