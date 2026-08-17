// Order service — the one service backed by RDS Postgres instead of
// DynamoDB (see docs/adr/0002-dynamodb-vs-rds.md for why). Publishes an
// "order placed" event to SNS after each successful order, which fans out
// to an email notification and the shipping SQS queue (see
// terraform/modules/notifications).
'use strict';

const express = require('express');
const { randomUUID } = require('crypto');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');
const { pool, ensureSchema } = require('./db');

const PORT = process.env.PORT || 8084;
const REGION = process.env.AWS_REGION || 'eu-west-2';
const ORDER_EVENTS_TOPIC_ARN = process.env.ORDER_EVENTS_TOPIC_ARN;

const sns = new SNSClient({ region: REGION });

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

app.get('/orders/:userId', async (req, res) => {
  try {
    const orders = await pool.query('SELECT * FROM orders WHERE user_id = $1 ORDER BY created_at DESC', [
      req.params.userId,
    ]);
    res.json(orders.rows);
  } catch (err) {
    console.error('list orders failed', err);
    res.status(500).json({ error: 'failed to list orders' });
  }
});

app.post('/orders', async (req, res) => {
  const { userId, items } = req.body || {};
  if (!userId || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'userId and a non-empty items array are required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const total = items.reduce((sum, i) => sum + i.unitPrice * i.quantity, 0);
    const orderId = randomUUID();

    await client.query(
      'INSERT INTO orders (id, user_id, status, total) VALUES ($1, $2, $3, $4)',
      [orderId, userId, 'PLACED', total]
    );

    for (const item of items) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES ($1, $2, $3, $4)',
        [orderId, item.productId, item.quantity, item.unitPrice]
      );
    }

    await client.query('COMMIT');

    // The order is already committed at this point — a notification
    // failure shouldn't turn into an error for the customer, so this is
    // deliberately fire-and-log rather than something that can fail the
    // request. If it matters that every order reliably gets an event
    // (e.g. for shipping), the more robust pattern is a transactional
    // outbox table polled by a separate worker — noted here as the "what
    // I'd do differently at scale" answer for this piece.
    if (ORDER_EVENTS_TOPIC_ARN) {
      try {
        await sns.send(
          new PublishCommand({
            TopicArn: ORDER_EVENTS_TOPIC_ARN,
            Subject: `Order ${orderId} placed`,
            Message: JSON.stringify({ orderId, userId, total, status: 'PLACED', items }),
            MessageAttributes: {
              eventType: { DataType: 'String', StringValue: 'order.placed' },
            },
          })
        );
      } catch (snsErr) {
        console.error('failed to publish order-placed event (order was still created)', snsErr);
      }
    }

    res.status(201).json({ orderId, total, status: 'PLACED' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('create order failed', err);
    res.status(500).json({ error: 'failed to create order' });
  } finally {
    client.release();
  }
});

ensureSchema()
  .then(() => {
    app.listen(PORT, () => console.log(`order-service listening on ${PORT}`));
  })
  .catch((err) => {
    console.error('failed to initialize schema, exiting', err);
    process.exit(1);
  });
