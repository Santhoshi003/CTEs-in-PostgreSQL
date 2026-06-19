WITH period_counts AS (
    SELECT u.user_id,
           1 AS period_order,
           COUNT(o.order_id)::int AS order_count
    FROM users u
    LEFT JOIN orders o
      ON o.user_id = u.user_id
     AND o.created_at >= current_date - INTERVAL '60 days'
     AND o.created_at < current_date - INTERVAL '30 days'
    GROUP BY u.user_id
    UNION ALL
    SELECT u.user_id,
           2 AS period_order,
           COUNT(o.order_id)::int AS order_count
    FROM users u
    LEFT JOIN orders o
      ON o.user_id = u.user_id
     AND o.created_at >= current_date - INTERVAL '30 days'
    GROUP BY u.user_id
)
SELECT user_id,
       order_count AS orders_last_30d,
       previous_order_count AS orders_prev_30d
FROM (
    SELECT user_id,
           period_order,
           order_count,
           LAG(order_count) OVER (PARTITION BY user_id ORDER BY period_order) AS previous_order_count
    FROM period_counts
) ranked
WHERE period_order = 2
  AND order_count < previous_order_count
ORDER BY user_id;
