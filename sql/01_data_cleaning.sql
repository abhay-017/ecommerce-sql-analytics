/* =====================================================================
   01. DATA QUALITY CHECKS, CLEANING & DATA MODEL
   Input : raw_transactions (1,067,371 rows loaded as-is from Excel)
   Output: transactions (clean line items), orders, customers, products
   ===================================================================== */

-- @query 01_data_quality: Data quality profile of the raw data
SELECT
    COUNT(*)                                                         AS total_rows,
    SUM(invoice LIKE 'C%')                                           AS cancellation_rows,
    SUM(customer_id IS NULL)                                         AS missing_customer_id,
    ROUND(100.0 * SUM(customer_id IS NULL) / COUNT(*), 1)            AS pct_missing_customer,
    SUM(quantity <= 0 AND invoice NOT LIKE 'C%')                     AS non_positive_qty_rows,
    SUM(price <= 0)                                                  AS non_positive_price_rows,
    COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT invoice, stock_code, description, quantity,
                                      invoice_date, price, customer_id, country
                                      FROM raw_transactions))        AS duplicate_rows
FROM raw_transactions;

-- @query 02_non_product_codes: Non-product stock codes (postage, fees, adjustments) to exclude
SELECT stock_code,
       MAX(description)                AS example_description,
       COUNT(*)                        AS row_count,
       ROUND(SUM(quantity * price), 0) AS net_value
FROM raw_transactions
WHERE UPPER(stock_code) IN ('POST', 'DOT', 'M', 'D', 'C2', 'S', 'B', 'BANK CHARGES', 'AMAZONFEE',
                            'CRUK', 'PADS', 'ADJUST', 'ADJUST2', 'TEST001', 'TEST002')
GROUP BY stock_code
ORDER BY row_count DESC;

-- @script build_model
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;

/* Clean sales line items:
   - drop cancelled invoices (start with 'C'), returns (qty <= 0) and zero/negative prices
   - drop postage, fees and manual adjustments (not product sales)
   - SELECT DISTINCT removes duplicate rows, incl. the 1-9 Dec 2010 overlap between the two Excel sheets */
CREATE TABLE transactions AS
SELECT DISTINCT
    invoice,
    stock_code,
    TRIM(description)                    AS description,
    quantity,
    price                                AS unit_price,
    ROUND(quantity * price, 2)           AS revenue,
    invoice_date                         AS invoice_ts,
    DATE(invoice_date)                   AS invoice_day,
    STRFTIME('%Y-%m', invoice_date)      AS invoice_month,
    customer_id,
    country
FROM raw_transactions
WHERE invoice NOT LIKE 'C%'
  AND quantity > 0
  AND price > 0
  AND UPPER(stock_code) NOT IN ('POST', 'DOT', 'M', 'D', 'C2', 'S', 'B', 'BANK CHARGES', 'AMAZONFEE',
                                'CRUK', 'PADS', 'ADJUST', 'ADJUST2', 'TEST001', 'TEST002');

CREATE INDEX ix_tx_invoice  ON transactions (invoice);
CREATE INDEX ix_tx_customer ON transactions (customer_id);
CREATE INDEX ix_tx_stock    ON transactions (stock_code);

-- One row per order (invoice)
CREATE TABLE orders AS
SELECT
    invoice,
    MAX(customer_id)                 AS customer_id,
    MAX(country)                     AS country,
    MIN(invoice_ts)                  AS order_ts,
    MIN(invoice_day)                 AS order_day,
    MIN(invoice_month)               AS order_month,
    COUNT(*)                         AS line_items,
    SUM(quantity)                    AS units,
    ROUND(SUM(revenue), 2)           AS order_value
FROM transactions
GROUP BY invoice;

CREATE INDEX ix_orders_customer ON orders (customer_id);

-- One row per identified customer
CREATE TABLE customers AS
WITH ranked AS (
    SELECT customer_id, country,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts) AS rn
    FROM orders
    WHERE customer_id IS NOT NULL
)
SELECT
    o.customer_id,
    r.country                         AS home_country,       -- country of the first order
    MIN(o.order_day)                  AS first_order_day,
    MAX(o.order_day)                  AS last_order_day,
    COUNT(*)                          AS total_orders,
    ROUND(SUM(o.order_value), 2)      AS total_revenue
FROM orders o
JOIN ranked r ON r.customer_id = o.customer_id AND r.rn = 1
GROUP BY o.customer_id, r.country;

-- Cancelled / returned product lines (kept separately so revenue can be reported net of returns)
DROP TABLE IF EXISTS returns;
CREATE TABLE returns AS
SELECT DISTINCT
    invoice,
    stock_code,
    -quantity                            AS units_returned,
    ROUND(-quantity * price, 2)          AS value_returned,
    DATE(invoice_date)                   AS return_day,
    customer_id,
    country
FROM raw_transactions
WHERE invoice LIKE 'C%'
  AND quantity < 0
  AND price > 0
  AND UPPER(stock_code) NOT IN ('POST', 'DOT', 'M', 'D', 'C2', 'S', 'B', 'BANK CHARGES', 'AMAZONFEE',
                                'CRUK', 'PADS', 'ADJUST', 'ADJUST2', 'TEST001', 'TEST002');

-- One row per product, labelled with its most frequent description, with gross and net revenue
CREATE TABLE products AS
WITH returned AS (
    SELECT stock_code, SUM(units_returned) AS units_returned, SUM(value_returned) AS value_returned
    FROM returns
    GROUP BY stock_code
),
desc_counts AS (
    SELECT stock_code, description, COUNT(*) AS n,
           ROW_NUMBER() OVER (PARTITION BY stock_code ORDER BY COUNT(*) DESC) AS rn
    FROM transactions
    WHERE description IS NOT NULL
    GROUP BY stock_code, description
)
SELECT
    t.stock_code,
    d.description,
    COUNT(DISTINCT t.invoice)         AS orders,
    SUM(t.quantity)                   AS units_sold,
    ROUND(SUM(t.revenue), 2)          AS revenue,
    ROUND(AVG(t.unit_price), 2)       AS avg_price,
    COALESCE(MAX(r.units_returned), 0)                         AS units_returned,
    ROUND(SUM(t.revenue) - COALESCE(MAX(r.value_returned), 0), 2) AS net_revenue
FROM transactions t
LEFT JOIN desc_counts d ON d.stock_code = t.stock_code AND d.rn = 1
LEFT JOIN returned r    ON r.stock_code = t.stock_code
GROUP BY t.stock_code, d.description;
-- @end

-- @query 03_clean_model_summary: Row counts after cleaning
SELECT 'raw_transactions' AS table_name, COUNT(*) AS row_count FROM raw_transactions
UNION ALL SELECT 'transactions (clean)', COUNT(*) FROM transactions
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'customers',            COUNT(*) FROM customers
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'returns',              COUNT(*) FROM returns;
