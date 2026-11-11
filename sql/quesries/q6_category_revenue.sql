-- Q6. Which categories contribute the most revenue?
-- Shows share of revenue, running (cumulative) share, and gross profit and margin, so a category
-- that sells a lot but earns little stands out.
SELECT category,
       ROUND(SUM(net_value), 2)                                                         AS revenue,
       ROUND(100 * SUM(net_value) / SUM(SUM(net_value)) OVER (), 1)                     AS pct_of_revenue,
       ROUND(100 * SUM(SUM(net_value)) OVER (ORDER BY SUM(net_value) DESC)
                 / SUM(SUM(net_value)) OVER (), 1)                                      AS cumulative_pct,
       ROUND(SUM(net_value - cost), 2)                                                  AS gross_profit,
       ROUND(100 * SUM(net_value - cost) / SUM(net_value), 1)                           AS gross_margin_pct
FROM v_sales_lines
WHERE returned = 0
GROUP BY category
ORDER BY revenue DESC;
