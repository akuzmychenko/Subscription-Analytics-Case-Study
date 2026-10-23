PRAGMA foreign_keys = ON;
CREATE TABLE settings (as_of TEXT NOT NULL CHECK (date(as_of) = as_of));
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    signup_date TEXT NOT NULL,
    country TEXT NOT NULL,
    channel TEXT NOT NULL CHECK (channel IN ('Organic', 'Paid Search', 'Social', 'Referral'))
);
CREATE TABLE plans (
    plan_id INTEGER PRIMARY KEY,
    plan_name TEXT NOT NULL UNIQUE,
    price_cents INTEGER NOT NULL CHECK (price_cents > 0),
    billing_days INTEGER NOT NULL CHECK (billing_days = 30)
);
CREATE TABLE subscriptions (
    subscription_id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(user_id),
    plan_id INTEGER NOT NULL REFERENCES plans(plan_id),
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL CHECK (end_date > start_date)
);
CREATE TABLE payments (
    payment_id INTEGER PRIMARY KEY,
    subscription_id INTEGER NOT NULL REFERENCES subscriptions(subscription_id),
    payment_date TEXT NOT NULL,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    status TEXT NOT NULL CHECK (status IN ('succeeded', 'failed'))
);
CREATE TABLE activity_events (
    event_id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    event_date TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type = 'content_view')
);
CREATE INDEX idx_payments_subscription_date ON payments(subscription_id, payment_date);
CREATE INDEX idx_activity_user_date ON activity_events(user_id, event_date);
CREATE INDEX idx_users_signup_date ON users(signup_date);
