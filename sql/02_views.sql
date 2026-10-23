-- One row per user. Aggregate payments BEFORE joining activity to avoid fan-out.
CREATE VIEW user_metrics AS
WITH first_payments AS (
    SELECT s.user_id, MIN(p.payment_date) AS first_payment_date,
           SUM(p.amount_cents) AS lifetime_cash_cents,
           COUNT(*) AS successful_payments
    FROM subscriptions s JOIN payments p USING (subscription_id)
    WHERE p.status = 'succeeded'
    GROUP BY s.user_id
)
SELECT u.*, substr(u.signup_date, 1, 7) AS signup_month,
       CASE WHEN date(u.signup_date, '+6 days') <= cfg.as_of THEN 1 ELSE 0 END AS eligible_7d,
       CASE WHEN f.first_payment_date >= u.signup_date
                  AND f.first_payment_date < date(u.signup_date, '+7 days') THEN 1 ELSE 0 END AS converted_7d,
       f.first_payment_date,
       COALESCE(f.lifetime_cash_cents, 0) AS lifetime_cash_cents,
       COALESCE(f.successful_payments, 0) AS successful_payments
FROM users u CROSS JOIN settings cfg LEFT JOIN first_payments f USING (user_id);

-- Calendar-month metrics. Conversion belongs to SIGNUP month; cash to PAYMENT month.
CREATE VIEW monthly_metrics AS
WITH RECURSIVE months(month_start) AS (
    SELECT date(MIN(signup_date), 'start of month') FROM users
    UNION ALL
    SELECT date(month_start, '+1 month') FROM months
    WHERE date(month_start, '+1 month') <= (SELECT as_of FROM settings)
), registrations AS (
    SELECT signup_month, COUNT(*) AS registrations,
           SUM(eligible_7d) AS eligible_users,
           SUM(CASE WHEN eligible_7d = 1 THEN converted_7d ELSE 0 END) AS converted_users
    FROM user_metrics GROUP BY signup_month
), cash AS (
    SELECT substr(payment_date,1,7) AS month, SUM(amount_cents) AS revenue_cents,
           COUNT(DISTINCT s.user_id) AS paying_users
    FROM payments p JOIN subscriptions s USING (subscription_id)
    WHERE status = 'succeeded' GROUP BY substr(payment_date,1,7)
), activity AS (
    SELECT substr(event_date,1,7) AS month, COUNT(DISTINCT user_id) AS active_users
    FROM activity_events GROUP BY substr(event_date,1,7)
), base AS (
    SELECT substr(m.month_start,1,7) AS month,
           COALESCE(r.registrations,0) AS registrations,
           COALESCE(r.eligible_users,0) AS eligible_users,
           COALESCE(r.converted_users,0) AS converted_users,
           COALESCE(c.revenue_cents,0) AS revenue_cents,
           COALESCE(c.paying_users,0) AS paying_users,
           COALESCE(a.active_users,0) AS active_users
    FROM months m LEFT JOIN registrations r ON r.signup_month = substr(m.month_start,1,7)
    LEFT JOIN cash c ON c.month = substr(m.month_start,1,7)
    LEFT JOIN activity a ON a.month = substr(m.month_start,1,7)
)
SELECT *, revenue_cents / 100.0 AS revenue_eur,
       1.0 * converted_users / NULLIF(eligible_users,0) AS conversion_7d,
       revenue_cents / 100.0 / NULLIF(paying_users,0) AS arppu_eur,
       LAG(revenue_cents) OVER (ORDER BY month) AS previous_revenue_cents,
       1.0 * revenue_cents / NULLIF(LAG(revenue_cents) OVER (ORDER BY month),0) - 1 AS revenue_mom
FROM base;

-- Activity retention by SIGNUP cohort, NOT subscriber renewal/churn.
-- Future, unobserved cells are NULL; observed cells without activity are zero.
CREATE VIEW cohort_retention AS
WITH RECURSIVE offsets(month_index) AS (
    VALUES(0) UNION ALL SELECT month_index + 1 FROM offsets WHERE month_index < 11
), cohorts AS (
    SELECT signup_month AS cohort_month, COUNT(*) AS cohort_size
    FROM user_metrics GROUP BY signup_month
), active AS (
    SELECT substr(u.signup_date,1,7) AS cohort_month,
           (CAST(strftime('%Y',e.event_date) AS INTEGER) - CAST(strftime('%Y',u.signup_date) AS INTEGER))*12
           + CAST(strftime('%m',e.event_date) AS INTEGER) - CAST(strftime('%m',u.signup_date) AS INTEGER) AS month_index,
           COUNT(DISTINCT u.user_id) AS active_users
    FROM users u JOIN activity_events e USING (user_id)
    GROUP BY 1,2
)
SELECT c.cohort_month, o.month_index, c.cohort_size,
       CASE WHEN date(c.cohort_month || '-01', '+' || o.month_index || ' months') <= cfg.as_of THEN 1 ELSE 0 END AS observed,
       CASE WHEN date(c.cohort_month || '-01', '+' || o.month_index || ' months') <= cfg.as_of THEN COALESCE(a.active_users,0) END AS active_users,
       CASE WHEN date(c.cohort_month || '-01', '+' || o.month_index || ' months') <= cfg.as_of THEN 1.0*COALESCE(a.active_users,0)/c.cohort_size END AS retention_rate
FROM cohorts c CROSS JOIN offsets o CROSS JOIN settings cfg
LEFT JOIN active a ON a.cohort_month=c.cohort_month AND a.month_index=o.month_index;

