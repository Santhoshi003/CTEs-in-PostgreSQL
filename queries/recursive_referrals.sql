WITH RECURSIVE top_users AS (
    SELECT o.user_id,
           COUNT(*)::int AS order_count
    FROM orders o
    GROUP BY o.user_id
    ORDER BY order_count DESC, o.user_id
    LIMIT 100
),
referral_chain AS (
    SELECT tu.user_id,
           u.referred_by,
           1 AS chain_depth,
           ARRAY[tu.user_id] AS visited_users
    FROM top_users tu
    JOIN users u ON u.user_id = tu.user_id
    UNION ALL
    SELECT rc.user_id,
           u.referred_by,
           rc.chain_depth + 1,
           rc.visited_users || u.user_id
    FROM referral_chain rc
    JOIN users u ON u.user_id = rc.referred_by
    WHERE rc.referred_by IS NOT NULL
      AND NOT u.user_id = ANY(rc.visited_users)
)
SELECT user_id,
       MAX(chain_depth) AS chain_depth
FROM referral_chain
GROUP BY user_id
ORDER BY chain_depth DESC, user_id;
