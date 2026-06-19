WITH lifetime_totals AS (
    SELECT o.user_id,
           SUM(o.amount)::numeric AS lifetime_total_spend
    FROM orders o
    GROUP BY o.user_id
)
SELECT o.order_id,
       o.user_id,
       o.amount,
       ROUND((o.amount / NULLIF(t.lifetime_total_spend, 0)) * 100, 2)::numeric AS lifetime_share_pct
FROM orders o
JOIN lifetime_totals t USING (user_id)
ORDER BY o.user_id, o.order_id;
