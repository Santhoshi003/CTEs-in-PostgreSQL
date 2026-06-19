SET synchronous_commit = OFF;
SET work_mem = '128MB';

INSERT INTO users (user_id, email, cohort_month, referred_by)
SELECT gs AS user_id,
       format('user%s@example.com', gs) AS email,
       (date_trunc('month', current_date - make_interval(months => floor(random() * 24)::int)))::date AS cohort_month,
       CASE
           WHEN gs = 1 THEN NULL
           WHEN gs % 11 = 0 THEN gs - 1
           WHEN random() < 0.35 THEN floor(1 + random() * (gs - 1))::int
           ELSE NULL
       END AS referred_by
FROM generate_series(1, 200000) AS gs;

INSERT INTO orders (order_id, user_id, product_id, amount, status, created_at, updated_at)
SELECT gen_random_uuid(),
       greatest(1, least(200000, floor(200000 * power(random(), 4))::int + 1)) AS user_id,
       floor(1 + random() * 5000)::int AS product_id,
       round((1 + random() * 499)::numeric, 2) AS amount,
       (ARRAY['pending', 'paid', 'shipped', 'completed', 'refunded'])[floor(1 + random() * 5)::int] AS status,
       ts AS created_at,
       ts + make_interval(days => floor(random() * 14)::int, hours => floor(random() * 24)::int) AS updated_at
FROM (
    SELECT now() - (random() * INTERVAL '730 days') AS ts
    FROM generate_series(1, 1000000)
) sampled_orders;

ANALYZE users;
ANALYZE orders;
