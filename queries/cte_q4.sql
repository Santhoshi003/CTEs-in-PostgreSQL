WITH prev_30d AS (
    SELECT u.user_id,
           COUNT(o.order_id)::int AS orders_prev_30d
    FROM users u
    LEFT JOIN orders o
      ON o.user_id = u.user_id
     AND o.created_at >= current_date - INTERVAL '60 days'
     AND o.created_at < current_date - INTERVAL '30 days'
    GROUP BY u.user_id
),
last_30d AS (
    SELECT u.user_id,
           COUNT(o.order_id)::int AS orders_last_30d
    FROM users u
    LEFT JOIN orders o
      ON o.user_id = u.user_id
     AND o.created_at >= current_date - INTERVAL '30 days'
    GROUP BY u.user_id
)
SELECT l.user_id,
       l.orders_last_30d,
       p.orders_prev_30d
FROM last_30d l
JOIN prev_30d p USING (user_id)
WHERE l.orders_last_30d < p.orders_prev_30d
ORDER BY l.user_id;
