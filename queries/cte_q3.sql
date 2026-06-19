WITH first_orders AS (
    SELECT DISTINCT ON (u.user_id)
           u.user_id,
           o.created_at AS first_order_date,
           o.amount AS first_order_amount
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.user_id
    ORDER BY u.user_id, o.created_at, o.order_id
),
last_orders AS (
    SELECT DISTINCT ON (u.user_id)
           u.user_id,
           o.created_at AS last_order_date,
           o.amount AS last_order_amount
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.user_id
    ORDER BY u.user_id, o.created_at DESC, o.order_id DESC
)
SELECT combined.user_id,
       MAX(combined.first_order_date) AS first_order_date,
       MAX(combined.last_order_date) AS last_order_date,
       MAX(combined.first_order_amount) AS first_order_amount,
       MAX(combined.last_order_amount) AS last_order_amount
FROM (
    SELECT user_id,
           first_order_date,
           NULL::timestamptz AS last_order_date,
           first_order_amount,
           NULL::numeric AS last_order_amount
    FROM first_orders
    UNION ALL
    SELECT user_id,
           NULL::timestamptz,
           last_order_date,
           NULL::numeric,
           last_order_amount
    FROM last_orders
) combined
GROUP BY combined.user_id
ORDER BY combined.user_id;
