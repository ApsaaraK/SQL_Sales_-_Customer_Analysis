-- Q2. What percentage of customers make another purchase?
-- A "purchase" is an order with at least one kept (non-returned) line.
-- The 90-day measure only includes customers whose first purchase is at least 90 days before
-- the as-of date, so recent customers are not unfairly counted as "did not return".
WITH params AS (
    SELECT DATE '2025-12-31' AS as_of
),
purchases AS (
    SELECT DISTINCT customer_id, order_id, order_date
    FROM v_sales_lines
    WHERE returned = 0
),
ranked AS (
    SELECT customer_id, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS n
    FROM purchases
),
per_customer AS (
    SELECT customer_id,
           COUNT(*)                                AS purchase_count,
           MIN(order_date) FILTER (WHERE n = 1)    AS first_date,
           MIN(order_date) FILTER (WHERE n = 2)    AS second_date
    FROM ranked
    GROUP BY customer_id
)
SELECT COUNT(*)                                                          AS customers_with_purchases,
       COUNT(second_date)                                                AS repeat_customers,
       ROUND(100.0 * COUNT(second_date) / COUNT(*), 1)                   AS repeat_rate_pct,
       ROUND(AVG(purchase_count), 2)                                     AS avg_purchases_per_customer,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY second_date - first_date))::numeric, 0)
                                                                         AS median_days_to_second_purchase,
       ROUND(100.0 * COUNT(*) FILTER (WHERE first_date <= p.as_of - 90 AND second_date <= first_date + 90)
             / NULLIF(COUNT(*) FILTER (WHERE first_date <= p.as_of - 90), 0), 1)
                                                                         AS repeat_within_90_days_pct
FROM per_customer
CROSS JOIN params p
GROUP BY p.as_of;
