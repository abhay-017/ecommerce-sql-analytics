/* =====================================================================
   04. COHORT RETENTION
   Business question: Of the customers acquired each month, what share
   comes back in the following months?
   Cohort = month of a customer's first order.
   ===================================================================== */

/* Note: the data starts in Dec 2009, so the Dec 2009 "cohort" also contains existing customers
   whose real first order was earlier, which is why its retention is much higher. */
-- @query 15_cohort_retention: Monthly cohort retention (% of cohort active N months later; blank = not yet observable)
WITH cohort AS (
    SELECT customer_id,
           STRFTIME('%Y-%m', first_order_day) AS cohort_month,
           CAST(STRFTIME('%Y', first_order_day) AS INTEGER) * 12
             + CAST(STRFTIME('%m', first_order_day) AS INTEGER) AS cohort_index
    FROM customers
),
activity AS (
    SELECT DISTINCT o.customer_id,
           c.cohort_month,
           CAST(STRFTIME('%Y', o.order_day) AS INTEGER) * 12
             + CAST(STRFTIME('%m', o.order_day) AS INTEGER) - c.cohort_index AS month_number
    FROM orders o
    JOIN cohort c ON c.customer_id = o.customer_id
    WHERE o.order_month < '2011-12'                       -- Dec 2011 is a partial month
),
cohort_size AS (
    SELECT cohort_month, MIN(cohort_index) AS cohort_index, COUNT(*) AS customers
    FROM cohort GROUP BY cohort_month
),
last_month AS (SELECT 2011 * 12 + 11 AS idx)              -- Nov 2011 = last full month
SELECT s.cohort_month,
       s.customers                                                                AS cohort_size,
       CASE WHEN s.cohort_index + 1  <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 1  THEN a.customer_id END) / s.customers, 1) END AS m1,
       CASE WHEN s.cohort_index + 2  <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 2  THEN a.customer_id END) / s.customers, 1) END AS m2,
       CASE WHEN s.cohort_index + 3  <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 3  THEN a.customer_id END) / s.customers, 1) END AS m3,
       CASE WHEN s.cohort_index + 6  <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 6  THEN a.customer_id END) / s.customers, 1) END AS m6,
       CASE WHEN s.cohort_index + 9  <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 9  THEN a.customer_id END) / s.customers, 1) END AS m9,
       CASE WHEN s.cohort_index + 12 <= l.idx THEN ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 12 THEN a.customer_id END) / s.customers, 1) END AS m12
FROM cohort_size s
CROSS JOIN last_month l
LEFT JOIN activity a ON a.cohort_month = s.cohort_month
WHERE s.cohort_month <= '2011-10'
GROUP BY s.cohort_month, s.customers, s.cohort_index, l.idx
ORDER BY s.cohort_month;

-- @query 16_retention_curve: Average retention by months since first order (all cohorts, full months only)
WITH RECURSIVE seq(n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 12
),
cohort AS (
    SELECT customer_id,
           CAST(STRFTIME('%Y', first_order_day) AS INTEGER) * 12
             + CAST(STRFTIME('%m', first_order_day) AS INTEGER) AS cohort_index
    FROM customers
),
activity AS (
    SELECT DISTINCT o.customer_id,
           CAST(STRFTIME('%Y', o.order_day) AS INTEGER) * 12
             + CAST(STRFTIME('%m', o.order_day) AS INTEGER) - c.cohort_index AS month_number
    FROM orders o
    JOIN cohort c ON c.customer_id = o.customer_id
    WHERE o.order_month < '2011-12'                       -- exclude the partial final month
),
max_index AS (
    SELECT 2011 * 12 + 11 AS last_full_index              -- Nov 2011
),
eligible AS (   -- customers whose cohort is old enough to be observed N months later
    SELECT seq.n AS month_number, COUNT(*) AS eligible_customers
    FROM cohort
    CROSS JOIN seq
    CROSS JOIN max_index
    WHERE cohort.cohort_index + seq.n <= max_index.last_full_index
    GROUP BY seq.n
)
-- Every activity row is already within the observed window, so it only needs matching on month_number
SELECT e.month_number,
       e.eligible_customers,
       COUNT(a.customer_id)                                          AS active_customers,
       ROUND(100.0 * COUNT(a.customer_id) / e.eligible_customers, 1) AS retention_pct
FROM eligible e
LEFT JOIN activity a ON a.month_number = e.month_number
GROUP BY e.month_number, e.eligible_customers
ORDER BY e.month_number;
