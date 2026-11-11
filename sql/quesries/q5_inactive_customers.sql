-- Q5. Which customers have become inactive?
-- Rule (change the numbers here to suit a client):
--   Active    = last purchase within 90 days of the as-of date
--   At risk   = 91 to 180 days
--   Inactive  = more than 180 days
--   Never purchased = in the customer table but no kept order (LEFT JOIN keeps them visible)
WITH params AS (
    SELECT DATE '2025-12-31' AS as_of
),
last_purchase AS (
    SELECT customer_id,
           MAX(order_date)           AS last_date,
           COUNT(DISTINCT order_id)  AS purchases,
           SUM(net_value)            AS lifetime_revenue
    FROM v_sales_lines
    WHERE returned = 0
    GROUP BY customer_id
),
status AS (
    SELECT c.customer_id, lp.purchases, lp.lifetime_revenue,
           p.as_of - lp.last_date AS days_since_last,
           CASE WHEN lp.last_date IS NULL            THEN 'Never purchased'
                WHEN p.as_of - lp.last_date <= 90    THEN '1 Active (0-90 days)'
                WHEN p.as_of - lp.last_date <= 180   THEN '2 At risk (91-180 days)'
                ELSE                                      '3 Inactive (180+ days)'
           END AS segment
    FROM customers c
    LEFT JOIN last_purchase lp USING (customer_id)
    CROSS JOIN params p
)
SELECT segment,
       COUNT(*)                                              AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_customers,
       COALESCE(ROUND(SUM(lifetime_revenue), 2), 0)          AS lifetime_revenue,
       COALESCE(ROUND(AVG(purchases), 1), 0)                 AS avg_purchases
FROM status
GROUP BY segment
ORDER BY segment;
