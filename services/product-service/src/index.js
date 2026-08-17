// Product service — catalog reads/writes against the DynamoDB products
// table. Config (table name, region) comes from environment variables set
// by the ECS task definition, which itself reads them from SSM Parameter
// Store at deploy time — this code never calls SSM directly.
'use strict';

const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  DeleteCommand,
} = require('@aws-sdk/lib-dynamodb');

const PORT = process.env.PORT || 8081;
const REGION = process.env.AWS_REGION || 'eu-west-2';
const TABLE_NAME = process.env.PRODUCTS_TABLE_NAME;

const ddbClient = new DynamoDBClient({ region: REGION });
const ddb = DynamoDBDocumentClient.from(ddbClient);

const app = express();
app.use(express.json());

// Health check — target group / ECS container health check hits this.
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// Public route (no auth required, matches the API Gateway design: GET
// /products is the one open route).
app.get('/products', async (req, res) => {
  try {
    if (req.query.category) {
      const result = await ddb.send(
        new QueryCommand({
          TableName: TABLE_NAME,
          IndexName: 'category-index',
          KeyConditionExpression: 'category = :c',
          ExpressionAttributeValues: { ':c': req.query.category },
        })
      );
      return res.json(result.Items || []);
    }
    const result = await ddb.send(new ScanCommand({ TableName: TABLE_NAME }));
    res.json(result.Items || []);
  } catch (err) {
    console.error('list products failed', err);
    res.status(500).json({ error: 'failed to list products' });
  }
});

app.get('/products/:id', async (req, res) => {
  try {
    const result = await ddb.send(
      new GetCommand({ TableName: TABLE_NAME, Key: { productId: req.params.id } })
    );
    if (!result.Item) return res.status(404).json({ error: 'not found' });
    res.json(result.Item);
  } catch (err) {
    console.error('get product failed', err);
    res.status(500).json({ error: 'failed to get product' });
  }
});

// Protected in front of API Gateway's Cognito JWT authorizer — this
// service trusts that anything reaching it past that point is authorized.
app.post('/products', async (req, res) => {
  const { productId, name, price, category, description, imageKey } = req.body || {};
  if (!productId || !name || price === undefined || !category) {
    return res.status(400).json({ error: 'productId, name, price, category are required' });
  }
  try {
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: { productId, name, price, category, description, imageKey },
      })
    );
    res.status(201).json({ productId });
  } catch (err) {
    console.error('create product failed', err);
    res.status(500).json({ error: 'failed to create product' });
  }
});

app.delete('/products/:id', async (req, res) => {
  try {
    await ddb.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { productId: req.params.id } }));
    res.status(204).end();
  } catch (err) {
    console.error('delete product failed', err);
    res.status(500).json({ error: 'failed to delete product' });
  }
});

app.listen(PORT, () => console.log(`product-service listening on ${PORT}`));
