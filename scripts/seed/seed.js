// Populates the demo product catalog: uploads one image per product to
// the product-images S3 bucket, then writes the product record to the
// DynamoDB products table.
//
// Image source, per product, in priority order:
//   1. A local file at scripts/seed/images/<productId>.<jpg|jpeg|png|webp>
//      — drop a royalty-free stock photo there (e.g. from Unsplash or
//      Pexels — NOT your own gear, see products.json's product names)
//      and it's used as-is.
//   2. Otherwise, a placehold.co-generated placeholder box (color-coded,
//      product name printed on it) — zero licensing risk, honest about
//      being a demo, but not what you want for portfolio screenshots.
// This means you can seed with all placeholders today and swap in real
// photos incrementally later — just re-run this script after dropping a
// new file in scripts/seed/images/.
//
// Run this on your own machine (not the Cowork sandbox) AFTER
// `terraform apply` — it needs the resources to already exist, and your
// AWS CLI credentials for account 264502359266.
//
// Usage:
//   cd scripts/seed
//   npm install
//   npm run seed
//
// Bucket/table names are looked up from SSM Parameter Store rather than
// hardcoded or copy-pasted from `terraform output`, so this works
// regardless of where you run it from.
'use strict';

const https = require('https');
const path = require('path');
const fs = require('fs');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');

const REGION = process.env.AWS_REGION || 'eu-west-2';
// SSM Parameter Store rejects any path starting with the reserved "aws"
// prefix, so the ssm-config/rds Terraform modules strip the leading
// "aws-" from the project name when building parameter paths. Match
// that here rather than the raw project name.
const PARAM_PREFIX = process.env.SSM_PARAM_PREFIX || '/ecommerce-platform/dev';

const LOCAL_IMAGES_DIR = path.join(__dirname, 'images');
const LOCAL_IMAGE_EXTENSIONS = [
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.png', 'image/png'],
  ['.webp', 'image/webp'],
];

const ssm = new SSMClient({ region: REGION });
const s3 = new S3Client({ region: REGION });
const ddbClient = new DynamoDBClient({ region: REGION });
const ddb = DynamoDBDocumentClient.from(ddbClient);

const products = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));

async function getParam(name) {
  const result = await ssm.send(new GetParameterCommand({ Name: `${PARAM_PREFIX}/${name}` }));
  return result.Parameter.Value;
}

function findLocalImage(productId) {
  for (const [ext, contentType] of LOCAL_IMAGE_EXTENSIONS) {
    const filePath = path.join(LOCAL_IMAGES_DIR, `${productId}${ext}`);
    if (fs.existsSync(filePath)) {
      return { buffer: fs.readFileSync(filePath), key: `images/${productId}${ext}`, contentType };
    }
  }
  return null;
}

// placehold.co generates a clean placeholder PNG on the fly — no real
// photo, no licensing question, and it's honest about being a demo
// catalog. Used only when no local file exists for this product.
function placeholderImageUrl(product) {
  const text = encodeURIComponent(product.name);
  return `https://placehold.co/800x800/${product.colorHex}/ffffff/png?text=${text}`;
}

function download(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`GET ${url} failed with status ${res.statusCode}`));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      })
      .on('error', reject);
  });
}

async function getImage(product) {
  const local = findLocalImage(product.productId);
  if (local) return { ...local, source: 'local' };

  const buffer = await download(placeholderImageUrl(product));
  return { buffer, key: `images/${product.productId}.png`, contentType: 'image/png', source: 'placeholder' };
}

async function seedProduct(product, bucketName, tableName) {
  const image = await getImage(product);

  await s3.send(
    new PutObjectCommand({
      Bucket: bucketName,
      Key: image.key,
      Body: image.buffer,
      ContentType: image.contentType,
    })
  );

  await ddb.send(
    new PutCommand({
      TableName: tableName,
      Item: {
        productId: product.productId,
        name: product.name,
        price: product.price,
        category: product.category,
        description: product.description,
        imageKey: image.key,
      },
    })
  );

  console.log(`seeded ${product.productId} — ${product.name} (${image.source})`);
}

// This script only ever PUTs the products currently listed in
// products.json — it has no way to know a product used to exist and was
// deleted from the list. Without this step, removing an entry from
// products.json and re-running `npm run seed` would leave its old
// DynamoDB item in place forever (still returned by GET /products'
// full-table Scan, still showing on the storefront) — that's the exact
// bug hit removing prod-006/prod-010. Reconcile by scanning the table
// and deleting anything whose productId isn't in the current list.
async function removeStaleProducts(tableName) {
  const currentIds = new Set(products.map((p) => p.productId));

  const scanResult = await ddb.send(new ScanCommand({ TableName: tableName, ProjectionExpression: 'productId' }));
  const staleIds = (scanResult.Items || [])
    .map((item) => item.productId)
    .filter((id) => !currentIds.has(id));

  for (const productId of staleIds) {
    // eslint-disable-next-line no-await-in-loop
    await ddb.send(new DeleteCommand({ TableName: tableName, Key: { productId } }));
    console.log(`removed ${productId} — no longer in products.json`);
  }

  // Deliberately NOT deleting the corresponding S3 image object here —
  // an orphaned image in the bucket is harmless (nothing links to it
  // once the DynamoDB item is gone) and this keeps the reconciliation
  // logic simple and safe; a stray unreferenced file is a much smaller
  // risk than a bug that deletes the wrong object.
}

async function main() {
  console.log('Looking up bucket/table names from SSM...');
  const [bucketName, tableName] = await Promise.all([
    getParam('s3/images_bucket'),
    getParam('dynamodb/products_table'),
  ]);
  console.log(`  images bucket: ${bucketName}`);
  console.log(`  products table: ${tableName}`);
  console.log(`  local images dir: ${LOCAL_IMAGES_DIR} (files here override the placeholder)`);
  console.log('');

  for (const product of products) {
    // eslint-disable-next-line no-await-in-loop
    await seedProduct(product, bucketName, tableName);
  }

  await removeStaleProducts(tableName);

  console.log(`\nDone — seeded ${products.length} products.`);
}

main().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
