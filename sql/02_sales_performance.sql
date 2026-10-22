/* =====================================================================
   02. SALES PERFORMANCE
   Business questions: How big is the business, how is it trending,
   where do sales come from, and when do customers buy?
   ===================================================================== */

-- @query 04_kpi_summary: Headline KPIs, Dec 2009 – Dec 2011
SELECT
    ROUND(SUM(order_value), 0)                       AS gross_revenue_gbp,
    ROUND((SELECT SUM(value_returned) FROM returns), 0)                     AS returns_gbp,
    ROUND(SUM(order_value) - (SELECT SUM(value_returned) FROM returns), 0)  AS net_revenue_gbp,
    COUNT(*)                                         AS total_orders,
    COUNT(DISTINCT customer_id)                      AS identified_customers,
    ROUND(AVG(order_value), 2)                       AS avg_order_value_gbp,
    SUM(units)                                       AS units_sold,
    ROUND(100.0 * SUM(CASE WHEN customer_id IS NULL THEN order_value END) / SUM(order_value), 1)
                                                     AS pct_revenue_guest_checkout
FROM orders;

-- @query 05_monthly_trend: Monthly revenue with month-on-month and year-on-year growth (LAG)
WITH monthly AS (
    SELECT order_month,
           ROUND(SUM(order_value), 0)  AS revenue,
           COUNT(*)                    AS orders,
           ROUND(AVG(order_value), 2)  AS avg_order_value
    FROM orders
    WHERE order_month < '2011-12'                 -- Dec 2011 is a partial month (data ends 9 Dec)
    GROUP BY order_month
)
SELECT order_month,
       revenue,
       orders,
       avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue, 1)  OVER (ORDER BY order_month)) / LAG(revenue, 1)  OVER (ORDER BY order_month), 1) AS mom_growth_pct,
       ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY order_month)) / LAG(revenue, 12) OVER (ORDER BY order_month), 1) AS yoy_growth_pct
FROM monthly
ORDER BY order_month;

-- @query 06_country_revenue: Top 10 countries by revenue, share of total and rank
WITH by_country AS (
    SELECT country,
           ROUND(SUM(order_value), 0)   AS revenue,
           COUNT(*)                     AS orders,
           COUNT(DISTINCT customer_id)  AS customers
    FROM orders
    GROUP BY country
)
SELECT RANK() OVER (ORDER BY revenue DESC)                     AS rank,
       country,
       revenue,
       orders,
       customers,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)        AS pct_of_revenue,
       ROUND(1.0 * revenue / orders, 0)                        AS revenue_per_order
FROM by_country
ORDER BY revenue DESC
LIMIT 10;

-- @query 07_uk_vs_international: Domestic vs international customers
SELECT CASE WHEN country = 'United Kingdom' THEN 'United Kingdom' ELSE 'International' END AS market,
       ROUND(SUM(order_value), 0)                                       AS revenue,
       COUNT(*)                                                         AS orders,
       ROUND(AVG(order_value), 0)                                       AS avg_order_value,
       ROUND(100.0 * SUM(order_value) / (SELECT SUM(order_value) FROM orders), 1) AS pct_of_revenue
FROM orders
GROUP BY market;

-- @query 08_weekday_pattern: Revenue and orders by day of week
SELECT CASE STRFTIME('%w', order_ts)
            WHEN '0' THEN '7 Sun' WHEN '1' THEN '1 Mon' WHEN '2' THEN '2 Tue' WHEN '3' THEN '3 Wed'
            WHEN '4' THEN '4 Thu' WHEN '5' THEN '5 Fri' WHEN '6' THEN '6 Sat' END   AS weekday,
       COUNT(*)                                                                    AS orders,
       ROUND(SUM(order_value), 0)                                                  AS revenue,
       ROUND(AVG(order_value), 0)                                                  AS avg_order_value
FROM orders
GROUP BY weekday
ORDER BY weekday;

-- @query 09_hourly_pattern: Orders by hour of day (when do customers order?)
SELECT CAST(STRFTIME('%H', order_ts) AS INTEGER)                 AS hour_of_day,
       COUNT(*)                                                 AS orders,
       ROUND(SUM(order_value), 0)                               AS revenue,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_orders
FROM orders
GROUP BY hour_of_day
ORDER BY hour_of_day;
