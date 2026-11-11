-- Q1. Which customers generate the most revenue?
-- Revenue is summed at order-line level (one row per line), THEN grouped by customer, so no
-- line is counted twice. Orders are counted with COUNT(DISTINCT order_id) because a customer's
-- order spans several lines. Returned lines are excluded (fully refunded).
WITH customer_revenue AS (
    SELECT customer_id,
           SUM(net_value)            AS revenue,
           COUNT(DISTINCT order_id)  AS orders
    FROM v_sales_lines
    WHERE returned = 0
    GROUP BY customer_id
)
SELECT RANK() OVER (ORDER BY cr.revenue DESC)              AS rank,
       c.customer_id,
       c.district,
       cr.orders,
       ROUND(cr.revenue, 2)                                AS revenue,
       ROUND(cr.revenue / cr.orders, 2)                    AS avg_order_value,
       ROUND(100 * cr.revenue / SUM(cr.revenue) OVER (), 2) AS pct_of_total_revenue
FROM customer_revenue cr
JOIN customers c USING (customer_id)
ORDER BY cr.revenue DESC, c.customer_id
LIMIT 10;
