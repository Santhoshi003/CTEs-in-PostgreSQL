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
SELECT current_day.day,
       current_day.daily_revenue,
       ROUND(AVG(prior_day.daily_revenue)::numeric, 2)::numeric AS rolling_7d_avg
FROM joined current_day
JOIN joined prior_day
  ON prior_day.day BETWEEN current_day.day - 6 AND current_day.day
GROUP BY current_day.day, current_day.daily_revenue
ORDER BY current_day.day;
