SELECT DISTINCT ON (u.user_id)
       u.user_id,
       FIRST_VALUE(o.created_at) OVER w AS first_order_date,
       LAST_VALUE(o.created_at) OVER w AS last_order_date,
       FIRST_VALUE(o.amount) OVER w AS first_order_amount,
       LAST_VALUE(o.amount) OVER w AS last_order_amount
FROM users u
LEFT JOIN orders o ON o.user_id = u.user_id
WINDOW w AS (
    PARTITION BY u.user_id
    ORDER BY o.created_at, o.order_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER BY u.user_id, o.created_at, o.order_id;
