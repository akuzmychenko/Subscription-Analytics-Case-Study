-- Run individual SELECT statements in DB Browser for SQLite or another SQL editor.

-- 1. Which channels bring registrations? Grouping and ordering.
SELECT channel, COUNT(*) AS registrations FROM users GROUP BY channel ORDER BY registrations DESC;

-- 2. Which plans collect the most cash? INNER JOIN, GROUP BY.
SELECT pl.plan_name, SUM(p.amount_cents)/100.0 AS cash_eur
FROM payments p JOIN subscriptions s USING(subscription_id) JOIN plans pl USING(plan_id)
WHERE p.status='succeeded' GROUP BY pl.plan_name ORDER BY cash_eur DESC;

-- 3. Which users never paid? A view with LEFT JOIN and NULL.
SELECT user_id, signup_date, channel FROM user_metrics WHERE first_payment_date IS NULL LIMIT 20;

-- 4. Fair 7-day conversion: exclude users without a complete observation window.
SELECT channel, COUNT(*) AS eligible_users, SUM(converted_7d) AS converted,
       1.0*SUM(converted_7d)/COUNT(*) AS conversion_rate
FROM user_metrics WHERE eligible_7d=1 GROUP BY channel;

-- 5. Who has above-average collected cash? Subquery.
SELECT user_id, lifetime_cash_cents/100.0 AS cash_eur FROM user_metrics
WHERE lifetime_cash_cents > (SELECT AVG(lifetime_cash_cents) FROM user_metrics);

-- 6. First and subsequent successful payments: ROW_NUMBER and LAG.
SELECT s.user_id,p.payment_date,
       ROW_NUMBER() OVER(PARTITION BY s.user_id ORDER BY p.payment_date,p.payment_id) AS payment_number,
       LAG(p.payment_date) OVER(PARTITION BY s.user_id ORDER BY p.payment_date,p.payment_id) AS previous_payment
FROM payments p JOIN subscriptions s USING(subscription_id) WHERE p.status='succeeded';

-- 7. Ranking channels by cash (NOT causal marketing effectiveness).
WITH channel_cash AS (
 SELECT channel,SUM(lifetime_cash_cents)/100.0 AS cash_eur FROM user_metrics GROUP BY channel
)
SELECT *,RANK() OVER(ORDER BY cash_eur DESC) AS cash_rank FROM channel_cash;

-- 8. Month-over-month cash trend: NULL for the first month or a zero denominator.
SELECT month,registrations,revenue_eur,revenue_mom FROM monthly_metrics;

-- 9. Observed cohort retention; future cells intentionally remain NULL.
SELECT * FROM cohort_retention ORDER BY cohort_month,month_index;

-- 10. Repeat payers: distinguish first conversion from ongoing payment behaviour.
SELECT COUNT(*) AS paying_users,
       SUM(CASE WHEN successful_payments>=2 THEN 1 ELSE 0 END) AS repeat_payers,
       1.0*SUM(CASE WHEN successful_payments>=2 THEN 1 ELSE 0 END)/COUNT(*) AS repeat_payer_share
FROM user_metrics WHERE successful_payments>=1;

-- 11. Check failed payment attempts; exclude these from collected cash.
SELECT status,COUNT(*) AS attempts,SUM(amount_cents)/100.0 AS attempted_eur FROM payments GROUP BY status;

-- 12. How much collected cash comes from first payments versus renewals?
WITH successful AS (
    SELECT s.user_id, p.payment_id, p.payment_date, p.amount_cents,
           ROW_NUMBER() OVER (
               PARTITION BY s.user_id ORDER BY p.payment_date, p.payment_id
           ) AS payment_number
    FROM payments p JOIN subscriptions s USING(subscription_id)
    WHERE p.status = 'succeeded'
), classified AS (
    SELECT CASE WHEN payment_number = 1 THEN 'First payment' ELSE 'Renewal' END AS payment_type,
           amount_cents
    FROM successful
)
SELECT payment_type, COUNT(*) AS successful_payments,
       SUM(amount_cents) / 100.0 AS cash_eur,
       1.0 * SUM(amount_cents) / NULLIF((SELECT SUM(amount_cents) FROM successful), 0) AS cash_share
FROM classified
GROUP BY payment_type
ORDER BY payment_type;
