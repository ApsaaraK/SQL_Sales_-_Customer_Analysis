-- 02_load.sql : load the CSV files (order matters because of the foreign keys)
-- Run from the project root so the relative paths resolve:  psql -d retail -f sql/02_load.sql

\copy customers   FROM 'data/customers.csv'   WITH (FORMAT csv, HEADER true)
\copy products    FROM 'data/products.csv'    WITH (FORMAT csv, HEADER true)
\copy orders      FROM 'data/orders.csv'      WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'data/order_items.csv' WITH (FORMAT csv, HEADER true)
