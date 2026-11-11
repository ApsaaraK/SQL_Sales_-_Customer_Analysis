-- 03_reconciliation.sql : proves the numbers are right, and shows how a join can silently inflate them.
-- One result set: group, check, value, expected, status.

WITH direct AS (   -- revenue straight from order_items, no joins at all
    SELECT SUM(quantity * list_price * (1 - discount_pct)) AS v
    FROM order_items WHERE returned = 0
),
revenue_checks AS (
    SELECT 'Revenue via the line view (3 tables joined)' AS check, SUM(net_value) AS v
      FROM v_sales_lines WHERE returned = 0
    UNION ALL
    SELECT 'Revenue summed customer by customer', SUM(r)
      FROM (SELECT customer_id, SUM(net_value) r FROM v_sales_lines WHERE returned = 0 GROUP BY customer_id) x
    UNION ALL
    SELECT 'Revenue summed month by month', SUM(r)
      FROM (SELECT DATE_TRUNC('month', order_date) m, SUM(net_value) r FROM v_sales_lines WHERE returned = 0 GROUP BY 1) x
    UNION ALL
    SELECT 'Revenue summed category by category', SUM(r)
      FROM (SELECT category, SUM(net_value) r FROM v_sales_lines WHERE returned = 0 GROUP BY category) x
    UNION ALL
    SELECT 'Revenue summed channel by channel', SUM(r)
      FROM (SELECT channel, SUM(net_value) r FROM v_sales_lines WHERE returned = 0 GROUP BY channel) x
),
order_counts AS (
    SELECT (SELECT COUNT(DISTINCT order_id) FROM order_items WHERE returned = 0)                     AS direct_orders,
           (SELECT COUNT(DISTINCT order_id) FROM v_sales_lines WHERE returned = 0)                   AS view_orders,
           (SELECT SUM(n) FROM (SELECT COUNT(DISTINCT order_id) n FROM v_sales_lines
                                WHERE returned = 0 GROUP BY DATE_TRUNC('month', order_date)) x)      AS monthly_orders
),
identity AS (
    SELECT SUM(quantity * list_price)                                                       AS gross,
           SUM(quantity * list_price * discount_pct)                                        AS discount,
           SUM(quantity * list_price * (1 - discount_pct)) FILTER (WHERE returned = 1)      AS returned_value
    FROM order_items
),
trap AS (
    -- WRONG ON PURPOSE: joining each line to every line of its order repeats the line once per sibling
    SELECT SUM(a.net_value) AS inflated_revenue, COUNT(a.order_id) AS naive_order_count
    FROM v_sales_lines a
    JOIN v_sales_lines b ON b.order_id = a.order_id
    WHERE a.returned = 0
)
SELECT 'Row counts' AS "group", 'View rows = order_items rows (joins add no rows)' AS check,
       (SELECT COUNT(*) FROM v_sales_lines)::numeric AS value,
       (SELECT COUNT(*) FROM order_items)::numeric   AS expected,
       CASE WHEN (SELECT COUNT(*) FROM v_sales_lines) = (SELECT COUNT(*) FROM order_items) THEN 'PASS' ELSE 'FAIL' END AS status
UNION ALL
SELECT 'Revenue', rc.check, ROUND(rc.v, 2), ROUND(d.v, 2),
       CASE WHEN ROUND(rc.v, 2) = ROUND(d.v, 2) THEN 'PASS' ELSE 'FAIL' END
FROM revenue_checks rc CROSS JOIN direct d
UNION ALL
SELECT 'Orders', 'Orders with a kept line: view vs direct', view_orders, direct_orders,
       CASE WHEN view_orders = direct_orders THEN 'PASS' ELSE 'FAIL' END FROM order_counts
UNION ALL
SELECT 'Orders', 'Monthly order counts add up to the total', monthly_orders, direct_orders,
       CASE WHEN monthly_orders = direct_orders THEN 'PASS' ELSE 'FAIL' END FROM order_counts
UNION ALL
SELECT 'Identity', 'Gross sales - discounts - returned value = revenue',
       ROUND(gross - discount - returned_value, 2), ROUND((SELECT v FROM direct), 2),
       CASE WHEN ROUND(gross - discount - returned_value, 2) = ROUND((SELECT v FROM direct), 2) THEN 'PASS' ELSE 'FAIL' END
FROM identity
UNION ALL
SELECT 'Trap (wrong on purpose)', 'Revenue after joining each line to all lines of its order',
       ROUND(inflated_revenue, 2), ROUND((SELECT v FROM direct), 2),
       'WRONG: ' || ROUND(100 * (inflated_revenue / (SELECT v FROM direct) - 1), 0) || '% too high'
FROM trap
UNION ALL
SELECT 'Trap (wrong on purpose)', 'COUNT(order_id) after the same join, instead of COUNT(DISTINCT)',
       naive_order_count, (SELECT direct_orders FROM order_counts),
       'WRONG: ' || ROUND(100 * (naive_order_count::numeric / (SELECT direct_orders FROM order_counts) - 1), 0) || '% too high'
FROM trap;
