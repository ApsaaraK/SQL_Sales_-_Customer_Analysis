-- 01_schema.sql : tables, constraints, indexes and the line-level view
-- Run from the project root:  psql -d retail -f sql/01_schema.sql

DROP VIEW  IF EXISTS v_sales_lines;
DROP TABLE IF EXISTS order_items, orders, products, customers CASCADE;

CREATE TABLE customers (
    customer_id  text PRIMARY KEY,
    district     text NOT NULL,
    province     text NOT NULL,
    signup_date  date NOT NULL
);

CREATE TABLE products (
    product_id    text PRIMARY KEY,
    product_name  text NOT NULL,
    category      text NOT NULL,
    list_price    numeric(12,2) NOT NULL CHECK (list_price > 0),
    unit_cost     numeric(12,2) NOT NULL CHECK (unit_cost > 0)
);

CREATE TABLE orders (
    order_id     text PRIMARY KEY,
    order_date   date NOT NULL,
    customer_id  text NOT NULL REFERENCES customers (customer_id),
    channel      text NOT NULL CHECK (channel IN ('Website', 'Mobile App', 'Marketplace'))
);

CREATE TABLE order_items (
    order_item_id  text PRIMARY KEY,
    order_id       text NOT NULL REFERENCES orders (order_id),
    product_id     text NOT NULL REFERENCES products (product_id),
    quantity       integer NOT NULL CHECK (quantity > 0),
    list_price     numeric(12,2) NOT NULL CHECK (list_price > 0),
    discount_pct   numeric(4,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 1),
    returned       smallint NOT NULL CHECK (returned IN (0, 1))
);

CREATE INDEX idx_orders_customer  ON orders (customer_id);
CREATE INDEX idx_orders_date      ON orders (order_date);
CREATE INDEX idx_items_order      ON order_items (order_id);
CREATE INDEX idx_items_product    ON order_items (product_id);

-- One row per order line. Both joins are many-to-one (a line has exactly one order and one
-- product), so this view has exactly as many rows as order_items and cannot double-count.
-- Money rules: net_value = quantity x list_price x (1 - discount). Returned lines are fully
-- refunded and restocked, so reports use WHERE returned = 0 for revenue and cost.
CREATE VIEW v_sales_lines AS
SELECT oi.order_item_id,
       oi.order_id,
       o.customer_id,
       o.order_date,
       o.channel,
       oi.product_id,
       p.product_name,
       p.category,
       oi.quantity,
       oi.quantity * oi.list_price                          AS gross_sales,
       oi.quantity * oi.list_price * (1 - oi.discount_pct)  AS net_value,
       oi.quantity * p.unit_cost                            AS cost,
       oi.returned
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id;
