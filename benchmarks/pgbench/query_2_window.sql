WITH user_spend AS (
    SELECT u.cohort_month,
           u.user_id,
           COALESCE(SUM(o.amount), 0)::numeric AS total_spend
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.user_id
    GROUP BY u.cohort_month, u.user_id
)
SELECT cohort_month,
       user_id,
       total_spend,
       rank_in_cohort
FROM (
    SELECT cohort_month,
           user_id,
           total_spend,
           ROW_NUMBER() OVER (PARTITION BY cohort_month ORDER BY total_spend DESC, user_id) AS rank_in_cohort
    FROM user_spend
) ranked
WHERE rank_in_cohort <= 10
ORDER BY cohort_month, rank_in_cohort, user_id;
