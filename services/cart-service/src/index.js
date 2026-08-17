// Cart service — per-user cart reads/writes against the DynamoDB cart
// table (userId partition key, productId sort key). Items TTL out via the
// table's expiresAt attribute rather than an explicit cleanup job.
'use strict';

const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
  DeleteCommand,
} = require('@aws-sdk/lib-dynamodb');

const PORT = process.env.PORT || 8082;
const REGION = process.env.AWS_REGION || 'eu-west-2';
const TABLE_NAME = process.env.CART_TABLE_NAME;
const CART_TTL_SECONDS = 60 * 60 * 24 * 7; // abandoned carts expire after 7 days

const ddbClient = new DynamoDBClient({ region: REGION });
const ddb = DynamoDBDocumentClient.from(ddbClient);

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// All cart routes sit behind the Cognito JWT authorizer at the API Gateway
// layer — userId here is expected to come from the caller (in production,
// from the verified JWT claims forwarded by API Gateway, not client input).
app.get('/cart/:userId', async (req, res) => {
  try {
    const result = await ddb.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'userId = :u',
        ExpressionAttributeValues: { ':u': req.params.userId },
      })
    );
    res.json(result.Items || []);
  } catch (err) {
    console.error('get cart failed', err);
    res.status(500).json({ error: 'failed to get cart' });
  }
});

app.post('/cart/:userId', async (req, res) => {
  const { productId, quantity } = req.body || {};
  if (!productId || !quantity) {
    return res.status(400).json({ error: 'productId and quantity are required' });
  }
  try {
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          userId: req.params.userId,
          productId,
          quantity,
          expiresAt: Math.floor(Date.now() / 1000) + CART_TTL_SECONDS,
        },
      })
    );
    res.status(201).json({ userId: req.params.userId, productId, quantity });
  } catch (err) {
    console.error('add to cart failed', err);
    res.status(500).json({ error: 'failed to add to cart' });
  }
});

app.delete('/cart/:userId/:productId', async (req, res) => {
  try {
    await ddb.send(
      new DeleteCommand({
        TableName: TABLE_NAME,
        Key: { userId: req.params.userId, productId: req.params.productId },
      })
    );
    res.status(204).end();
  } catch (err) {
    console.error('remove from cart failed', err);
    res.status(500).json({ error: 'failed to remove from cart' });
  }
});

app.listen(PORT, () => console.log(`cart-service listening on ${PORT}`));
