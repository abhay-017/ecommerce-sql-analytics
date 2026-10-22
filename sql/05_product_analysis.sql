/* =====================================================================
   05. PRODUCT ANALYSIS
   Business questions: Which products drive revenue, how concentrated is
   the catalogue, which products get returned, and what sells together?
   ===================================================================== */

/* Gross revenue is misleading: some "best sellers" were huge orders that were cancelled in full.
   This query shows the products whose ranking changes most once returns are netted off. */
-- @query 17a_gross_vs_net: Why net revenue matters: top products by gross revenue vs their net revenue
SELECT RANK() OVER (ORDER BY revenue DESC)                   AS gross_rank,
       stock_code,
       description,
       orders,
       revenue                                               AS gross_revenue,
       net_revenue,
       ROUND(100.0 * units_returned / units_sold, 1)         AS pct_units_returned
FROM products
ORDER BY revenue DESC
LIMIT 10;

-- @query 17_top_products: Top 10 products by NET revenue (after returns)
SELECT RANK() OVER (ORDER BY net_revenue DESC)               AS rank,
       stock_code,
       description,
       units_sold - units_returned                           AS net_units,
       orders,
       net_revenue,
       avg_price,
       ROUND(100.0 * net_revenue / SUM(net_revenue) OVER (), 2) AS pct_of_net_revenue
FROM products
ORDER BY net_revenue DESC
LIMIT 10;

-- @query 18_pareto: Pareto (80/20) analysis: how many products make 80% of revenue?
WITH ranked AS (
    SELECT stock_code,
           net_revenue,
           ROW_NUMBER() OVER (ORDER BY net_revenue DESC)                                AS product_rank,
           COUNT(*) OVER ()                                                             AS total_products,
           SUM(net_revenue) OVER (ORDER BY net_revenue DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(net_revenue) OVER ()                                                 AS cumulative_share
    FROM products
    WHERE net_revenue > 0
)
SELECT threshold_pct,
       MIN(product_rank)                                             AS products_needed,
       MAX(total_products)                                           AS total_products,
       ROUND(100.0 * MIN(product_rank) / MAX(total_products), 1)     AS pct_of_catalogue
FROM ranked
JOIN (SELECT 50 AS threshold_pct UNION ALL SELECT 80 UNION ALL SELECT 95) t
  ON cumulative_share >= t.threshold_pct / 100.0
GROUP BY threshold_pct
ORDER BY threshold_pct;

-- @query 19_return_rates: Products with the highest return (cancellation) rates, min. 1,000 units sold
SELECT stock_code,
       description,
       units_sold,
       units_returned,
       ROUND(100.0 * units_returned / units_sold, 1)    AS return_rate_pct,
       orders
FROM products
WHERE units_sold >= 1000
ORDER BY return_rate_pct DESC
LIMIT 10;

-- @query 20_bought_together: Product pairs most often bought in the same order (top 150 products)
WITH top_products AS (
    SELECT stock_code FROM products ORDER BY orders DESC LIMIT 150
),
basket AS (
    SELECT DISTINCT t.invoice, t.stock_code
    FROM transactions t
    JOIN top_products tp ON tp.stock_code = t.stock_code
)
SELECT a.stock_code                                   AS product_a,
       pa.description                                 AS description_a,
       b.stock_code                                   AS product_b,
       pb.description                                 AS description_b,
       COUNT(*)                                       AS orders_together,
       ROUND(100.0 * COUNT(*) / pa.orders, 1)         AS pct_of_a_orders_with_b
FROM basket a
JOIN basket b      ON a.invoice = b.invoice AND a.stock_code < b.stock_code
JOIN products pa   ON pa.stock_code = a.stock_code
JOIN products pb   ON pb.stock_code = b.stock_code
GROUP BY a.stock_code, b.stock_code
ORDER BY orders_together DESC
LIMIT 10;
