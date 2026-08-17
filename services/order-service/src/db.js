// Connection pool + one-time schema bootstrap for the orders table. The DB
// password is injected by ECS as a "secret" (from the SSM SecureString
// param via the task execution role) rather than a plain environment
// variable — it only ever exists as process.env.DB_PASSWORD inside the
// running container, never in the task definition or Terraform state in
// plaintext.
'use strict';

const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  max: 5,
  ssl: { rejectUnauthorized: false }, // RDS uses a rotating AWS CA; skip strict verification for portfolio simplicity
});

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'PLACED',
      total NUMERIC(10, 2) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS order_items (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      unit_price NUMERIC(10, 2) NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
  `);
}

module.exports = { pool, ensureSchema };
