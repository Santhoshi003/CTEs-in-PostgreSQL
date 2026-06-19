CREATE TABLE users (
    user_id INT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    cohort_month DATE NOT NULL,
    referred_by INT NULL REFERENCES users(user_id)
);

CREATE TABLE orders (
    order_id UUID PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(user_id),
    product_id INT NOT NULL,
    amount NUMERIC NOT NULL CHECK (amount > 0),
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
