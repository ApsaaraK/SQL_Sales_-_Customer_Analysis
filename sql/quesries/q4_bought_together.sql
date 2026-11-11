-- Q4. Which products are commonly bought together?
-- Pitfall avoided: the same product can appear on two lines of one order. Self-joining raw order
-- lines would then count that order's pair twice. So the pairs are built from DISTINCT
-- (order, product) first. Each pair is counted once (product_a < product_b).
-- Lift = how much more often the pair occurs than chance, given each product's popularity.
-- Lift near 1.0 means the pair is common only because both products are popular.
WITH order_products AS (
    SELECT DISTINCT order_id, product_id
    FROM order_items
    WHERE returned = 0
),
totals AS (
    SELECT COUNT(DISTINCT order_id) AS total_orders FROM order_products
),
product_orders AS (
    SELECT product_id, COUNT(*) AS orders_with_product
    FROM order_products
    GROUP BY product_id
),
pairs AS (
    SELECT a.product_id AS product_a, b.product_id AS product_b, COUNT(*) AS orders_together
    FROM order_products a
    JOIN order_products b ON b.order_id = a.order_id AND a.product_id < b.product_id
    GROUP BY a.product_id, b.product_id
)
SELECT pa.product_name                                              AS product_a,
       pb.product_name                                              AS product_b,
       p.orders_together,
       ROUND(100.0 * p.orders_together / t.total_orders, 2)         AS pct_of_orders,
       ROUND((p.orders_together::numeric / t.total_orders)
             / ((qa.orders_with_product::numeric / t.total_orders)
                * (qb.orders_with_product::numeric / t.total_orders)), 2) AS lift
FROM pairs p
CROSS JOIN totals t
JOIN product_orders qa ON qa.product_id = p.product_a
JOIN product_orders qb ON qb.product_id = p.product_b
JOIN products pa ON pa.product_id = p.product_a
JOIN products pb ON pb.product_id = p.product_b
ORDER BY p.orders_together DESC, pa.product_name, pb.product_name
LIMIT 10;
