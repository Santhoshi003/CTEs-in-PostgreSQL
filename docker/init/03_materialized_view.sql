CREATE MATERIALIZED VIEW daily_revenue_stats AS
WITH calendar AS (
    SELECT generate_series(current_date - INTERVAL '89 days', current_date, INTERVAL '1 day')::date AS day
),
daily_revenue AS (
    SELECT o.created_at::date AS day,
           SUM(o.amount)::numeric AS daily_revenue
    FROM orders o
    WHERE o.created_at >= current_date - INTERVAL '89 days'
    GROUP BY 1
),
joined AS (
    SELECT c.day,
           COALESCE(d.daily_revenue, 0)::numeric AS daily_revenue
    FROM calendar c
    LEFT JOIN daily_revenue d ON d.day = c.day
)
SELECT day,
       daily_revenue,
       ROUND(AVG(daily_revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)::numeric AS rolling_7d_avg
FROM joined
ORDER BY day;

CREATE UNIQUE INDEX daily_revenue_stats_day_idx ON daily_revenue_stats (day);
