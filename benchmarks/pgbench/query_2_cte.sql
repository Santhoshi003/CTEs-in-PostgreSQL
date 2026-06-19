WITH user_spend AS (
    SELECT u.cohort_month,
           u.user_id,
           COALESCE(SUM(o.amount), 0)::numeric AS total_spend
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.user_id
    GROUP BY u.cohort_month, u.user_id
),
cohorts AS (
    SELECT DISTINCT cohort_month
    FROM users
)
SELECT ranked.cohort_month,
       ranked.user_id,
       ranked.total_spend,
       ranked.rank_in_cohort
FROM cohorts c
CROSS JOIN LATERAL (
    SELECT us.cohort_month,
           us.user_id,
           us.total_spend,
           ROW_NUMBER() OVER (ORDER BY us.total_spend DESC, us.user_id) AS rank_in_cohort
    FROM user_spend us
    WHERE us.cohort_month = c.cohort_month
    ORDER BY us.total_spend DESC, us.user_id
    LIMIT 10
) ranked
ORDER BY ranked.cohort_month, ranked.rank_in_cohort, ranked.user_id;
