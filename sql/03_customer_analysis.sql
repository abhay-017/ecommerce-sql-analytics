/* =====================================================================
   03. CUSTOMER ANALYSIS
   Business questions: Who are the most valuable customers, how many come
   back, and which customer segments should marketing focus on?
   (Identified customers only: guest orders have no customer ID.)
   ===================================================================== */

-- @query 10_top_customers: Top 10 customers by revenue and their share of total
SELECT customer_id,
       home_country,
       total_orders,
       total_revenue,
       ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2)                         AS pct_of_customer_revenue,
       ROUND(100.0 * SUM(total_revenue) OVER (ORDER BY total_revenue DESC
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / SUM(total_revenue) OVER (), 2)                                        AS cumulative_pct
FROM customers
ORDER BY total_revenue DESC
LIMIT 10;

-- @query 11_customer_concentration: How concentrated is revenue? (customer deciles)
WITH deciles AS (
    SELECT customer_id, total_revenue,
           NTILE(10) OVER (ORDER BY total_revenue DESC) AS decile
    FROM customers
)
SELECT decile                                                          AS customer_decile,
       COUNT(*)                                                        AS customers,
       ROUND(SUM(total_revenue), 0)                                    AS revenue,
       ROUND(100.0 * SUM(total_revenue) / (SELECT SUM(total_revenue) FROM customers), 1) AS pct_of_revenue
FROM deciles
GROUP BY decile
ORDER BY decile;

-- @query 12_repeat_purchase: Repeat purchase behaviour (order-count buckets)
SELECT CASE WHEN total_orders = 1  THEN '1 order'
            WHEN total_orders <= 3 THEN '2-3 orders'
            WHEN total_orders <= 10 THEN '4-10 orders'
            ELSE '11+ orders' END                                       AS order_bucket,
       COUNT(*)                                                         AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_of_customers,
       ROUND(SUM(total_revenue), 0)                                     AS revenue,
       ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 1) AS pct_of_revenue
FROM customers
GROUP BY order_bucket
ORDER BY MIN(total_orders);

/* RFM segmentation
   Recency   = days since last order (as of the day after the data ends)
   Frequency = number of orders,  Monetary = total revenue
   Each is scored 1-5 with NTILE (5 = best), then mapped to named segments. */
-- @query 13_rfm_segments: RFM customer segmentation
WITH ref AS (
    SELECT DATE(MAX(order_day), '+1 day') AS ref_day FROM orders
),
rfm AS (
    SELECT c.customer_id,
           CAST(JULIANDAY(ref.ref_day) - JULIANDAY(c.last_order_day) AS INTEGER) AS recency_days,
           c.total_orders  AS frequency,
           c.total_revenue AS monetary
    FROM customers c CROSS JOIN ref
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,      -- most recent -> 5
           NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm
),
segmented AS (
    SELECT *,
           CASE
               WHEN r_score >= 4 AND f_score >= 4                    THEN 'Champions'
               WHEN r_score >= 3 AND f_score >= 3                    THEN 'Loyal Customers'
               WHEN r_score >= 4 AND f_score <= 2                    THEN 'New / Promising'
               WHEN r_score <= 2 AND f_score >= 3                    THEN 'At Risk'
               WHEN r_score = 3  AND f_score <= 2                    THEN 'Need Attention'
               ELSE                                                       'Hibernating / Lost'
           END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                                         AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_of_customers,
       ROUND(AVG(recency_days), 0)                                      AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                         AS avg_orders,
       ROUND(AVG(monetary), 0)                                          AS avg_revenue,
       ROUND(SUM(monetary), 0)                                          AS total_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)     AS pct_of_revenue
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;

-- @query 14_new_vs_returning: Monthly revenue from new vs returning customers
WITH first_month AS (
    SELECT customer_id, STRFTIME('%Y-%m', first_order_day) AS cohort_month FROM customers
)
SELECT o.order_month,
       COUNT(DISTINCT CASE WHEN o.order_month =  f.cohort_month THEN o.customer_id END) AS new_customers,
       COUNT(DISTINCT CASE WHEN o.order_month <> f.cohort_month THEN o.customer_id END) AS returning_customers,
       ROUND(SUM(CASE WHEN o.order_month =  f.cohort_month THEN o.order_value ELSE 0 END), 0) AS new_revenue,
       ROUND(SUM(CASE WHEN o.order_month <> f.cohort_month THEN o.order_value ELSE 0 END), 0) AS returning_revenue,
       ROUND(100.0 * SUM(CASE WHEN o.order_month <> f.cohort_month THEN o.order_value ELSE 0 END)
                   / SUM(o.order_value), 1)                                              AS pct_revenue_returning
FROM orders o
JOIN first_month f ON f.customer_id = o.customer_id
WHERE o.order_month < '2011-12'
GROUP BY o.order_month
ORDER BY o.order_month;
