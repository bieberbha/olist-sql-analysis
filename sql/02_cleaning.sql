-- Olist SQL Analysis | 02_cleaning.sql | Data quality checks (SQLite)

-- Row counts after import
SELECT 'customers' AS tbl, COUNT(*) AS n FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews;

-- Check 1: Order status distribution
SELECT order_status, COUNT(*) AS n
FROM orders
GROUP BY order_status
ORDER BY n DESC;

-- Check 2: Missing approval / delivery dates
SELECT
    SUM(CASE WHEN order_approved_at IS NULL OR order_approved_at = '' THEN 1 ELSE 0 END) AS no_approval,
    SUM(CASE WHEN order_delivered_customer_date IS NULL OR order_delivered_customer_date = '' THEN 1 ELSE 0 END) AS no_delivery_date
FROM orders;

-- Check 3: Delivered orders with no delivery date (real data issue)
SELECT COUNT(*) AS suspicious
FROM orders
WHERE order_status = 'delivered'
  AND (order_delivered_customer_date IS NULL OR order_delivered_customer_date = '');

-- Check 4: Orders with no items
SELECT COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items i ON o.order_id = i.order_id
WHERE i.order_id IS NULL;

-- Check 4b: Status breakdown of those orders
SELECT o.order_status, COUNT(*) AS n
FROM orders o
LEFT JOIN order_items i ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY n DESC;

-- Check 5: Orders with more than one review
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
);

-- Check 6: Products with no category
SELECT COUNT(*) AS no_category
FROM products
WHERE product_category_name IS NULL OR product_category_name = '';

-- Check 7: Date format sanity check
SELECT order_purchase_timestamp, order_delivered_customer_date, order_estimated_delivery_date
FROM orders
LIMIT 5;
