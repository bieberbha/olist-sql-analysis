-- Olist SQL Analysis | 03_analysis.sql | Business questions (SQLite)
-- Run ONE query at a time: click inside it, then press Shift+F5
-- (or select its text and press Ctrl+Enter).

------------------------------------------------------------
-- BASIC
------------------------------------------------------------

-- Q1: Monthly revenue and order count
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS month,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(p.payment_value), 2) AS revenue
FROM orders o
JOIN order_payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY 1
ORDER BY 1;

-- Q2: Top 10 product categories by revenue
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(DISTINCT i.order_id) AS orders,
    ROUND(SUM(i.price), 2) AS revenue
FROM order_items i
JOIN orders o ON i.order_id = o.order_id
JOIN products p ON i.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY 1
ORDER BY revenue DESC
LIMIT 10;

-- Q3: Revenue by customer state
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(p.payment_value), 2) AS revenue,
    ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 2) AS pct_of_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY 1
ORDER BY revenue DESC;

-- Q4: Average payment value by payment type
SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(payment_value), 2) AS avg_payment
FROM order_payments
GROUP BY payment_type
ORDER BY orders DESC;

------------------------------------------------------------
-- INTERMEDIATE
------------------------------------------------------------

-- Q5: Actual vs estimated delivery time by state (days)
SELECT
    c.customer_state,
    COUNT(*) AS orders,
    ROUND(AVG(julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)), 1) AS avg_actual_days,
    ROUND(AVG(julianday(o.order_estimated_delivery_date) - julianday(o.order_purchase_timestamp)), 1) AS avg_estimated_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND NULLIF(o.order_delivered_customer_date, '') IS NOT NULL
GROUP BY 1
ORDER BY avg_actual_days DESC;

-- Q6: Late deliveries and their effect on review score
-- (reviews reduced to one score per order to avoid double counting)
WITH review_per_order AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
delivered AS (
    SELECT order_id,
           CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
                THEN 'late' ELSE 'on_time' END AS delivery_status
    FROM orders
    WHERE order_status = 'delivered'
      AND NULLIF(order_delivered_customer_date, '') IS NOT NULL
)
SELECT
    d.delivery_status,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders,
    ROUND(AVG(r.score), 2) AS avg_review_score
FROM delivered d
JOIN review_per_order r ON d.order_id = r.order_id
GROUP BY 1;

-- Q7: Top 10 sellers by revenue with average rating
WITH review_per_order AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
seller_rev AS (
    SELECT i.seller_id, ROUND(SUM(i.price), 2) AS revenue, COUNT(DISTINCT i.order_id) AS orders
    FROM order_items i
    JOIN orders o ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY i.seller_id
),
seller_rating AS (
    SELECT so.seller_id, ROUND(AVG(r.score), 2) AS avg_rating
    FROM (SELECT DISTINCT i.seller_id, i.order_id
          FROM order_items i
          JOIN orders o ON i.order_id = o.order_id
          WHERE o.order_status = 'delivered') so
    JOIN review_per_order r ON so.order_id = r.order_id
    GROUP BY so.seller_id
)
SELECT sr.seller_id, s.seller_state, sr.orders, sr.revenue, rt.avg_rating
FROM seller_rev sr
JOIN sellers s ON sr.seller_id = s.seller_id
LEFT JOIN seller_rating rt ON sr.seller_id = rt.seller_id
ORDER BY sr.revenue DESC
LIMIT 10;

-- Q8: Repeat customer rate (uses customer_unique_id, NOT customer_id)
WITH cust AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS n_orders
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM cust;

------------------------------------------------------------
-- ADVANCED (window functions)
------------------------------------------------------------

-- Q9: Month-over-month revenue growth (LAG)
WITH monthly AS (
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS month,
           SUM(p.payment_value) AS revenue
    FROM orders o
    JOIN order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY month), 2) AS prev_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 2) AS growth_pct
FROM monthly
ORDER BY month;

-- Q10: Top 3 products by revenue within each category (RANK)
WITH prod_rev AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
        i.product_id,
        ROUND(SUM(i.price), 2) AS revenue
    FROM order_items i
    JOIN orders o ON i.order_id = o.order_id
    JOIN products p ON i.product_id = p.product_id
    LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY 1, 2
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
    FROM prod_rev
)
SELECT category, product_id, revenue, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY category, rnk;

-- Q11: Running (cumulative) revenue by month
WITH monthly AS (
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS month,
           SUM(p.payment_value) AS revenue
    FROM orders o
    JOIN order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS running_total
FROM monthly
ORDER BY month;

-- Q12: Cohort retention (months 0-6 after first purchase)
WITH orders_c AS (
    SELECT c.customer_unique_id,
           strftime('%Y-%m', o.order_purchase_timestamp) AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
first_order AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort
    FROM orders_c
    GROUP BY 1
),
activity AS (
    SELECT DISTINCT
        oc.customer_unique_id,
        f.cohort,
        (CAST(substr(oc.order_month, 1, 4) AS INTEGER) * 12 + CAST(substr(oc.order_month, 6, 2) AS INTEGER))
      - (CAST(substr(f.cohort, 1, 4) AS INTEGER) * 12 + CAST(substr(f.cohort, 6, 2) AS INTEGER)) AS month_number
    FROM orders_c oc
    JOIN first_order f ON oc.customer_unique_id = f.customer_unique_id
),
cohort_size AS (
    SELECT cohort, COUNT(*) AS size
    FROM first_order
    GROUP BY 1
)
SELECT
    a.cohort,
    cs.size AS cohort_size,
    a.month_number,
    COUNT(DISTINCT a.customer_unique_id) AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT a.customer_unique_id) / cs.size, 2) AS retention_pct
FROM activity a
JOIN cohort_size cs ON a.cohort = cs.cohort
WHERE a.month_number BETWEEN 0 AND 6
GROUP BY a.cohort, a.month_number
ORDER BY a.cohort, a.month_number;

-- Q13: RFM segmentation
WITH cust AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value) AS monetary
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
),
rfm AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,
        julianday((SELECT MAX(order_purchase_timestamp) FROM orders)) - julianday(last_order) AS recency_days
    FROM cust
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r,   -- 4 = most recent
        CASE WHEN frequency >= 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f,
        NTILE(4) OVER (ORDER BY monetary) AS m              -- 4 = highest spend
    FROM rfm
),
segmented AS (
    SELECT *,
        CASE
            WHEN r >= 3 AND f >= 2 THEN 'Champions'
            WHEN r >= 3 AND f = 1 AND m >= 3 THEN 'New High-Value'
            WHEN r >= 3 AND f = 1 THEN 'New Customers'
            WHEN r <= 2 AND f >= 2 THEN 'At Risk'
            WHEN r <= 2 AND m >= 3 THEN 'Lost High-Value'
            ELSE 'Lost / Low-Value'
        END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_spend
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;
