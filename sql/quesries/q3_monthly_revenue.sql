-- Q3. How does monthly revenue change?
-- Month-over-month and year-over-year change use LAG(). The 3-month moving average is left
-- blank for the first two months because it would be based on fewer than three months.
WITH monthly AS (
    SELECT DATE_TRUNC('month', order_date)::date AS month,
           SUM(net_value)                        AS revenue,
           COUNT(DISTINCT order_id)              AS orders
    FROM v_sales_lines
    WHERE returned = 0
    GROUP BY 1
)
SELECT TO_CHAR(month, 'YYYY-MM')                                              AS month,
       ROUND(revenue, 2)                                                      AS revenue,
       orders,
       ROUND(100 * (revenue - LAG(revenue)     OVER w) / LAG(revenue)     OVER w, 1) AS mom_change_pct,
       CASE WHEN ROW_NUMBER() OVER w >= 3
            THEN ROUND(AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
       END                                                                    AS moving_avg_3m,
       ROUND(100 * (revenue - LAG(revenue, 12) OVER w) / LAG(revenue, 12) OVER w, 1) AS yoy_change_pct
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;
