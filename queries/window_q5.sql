SELECT o.order_id,
       o.user_id,
       o.amount,
       ROUND((o.amount / NULLIF(SUM(o.amount) OVER (PARTITION BY o.user_id), 0)) * 100, 2)::numeric AS lifetime_share_pct
FROM orders o
ORDER BY o.user_id, o.order_id;
