# ADR 0002: DynamoDB for products/cart, RDS Postgres for orders

## Status
Accepted.

## Context
The app has three data domains with different access patterns:

- **Products** (catalog): read-heavy, simple lookups by ID or category, schema is stable and shallow (name, price, description, image, category). No cross-entity joins.
- **Cart**: per-user, ephemeral, high write-to-read ratio relative to its size, naturally keyed by `(userId, productId)`, and should just disappear after a period of inactivity.
- **Orders**: relational by nature — an order has line items, a user, a status history, and needs to support queries like "all orders for a user in a date range" or "total revenue by day," plus multi-row consistency when an order is placed (decrement-adjacent logic, even if inventory itself lives elsewhere).

## Decision
Use DynamoDB for products and cart; RDS Postgres for orders.

- **Products**: `PAY_PER_REQUEST` DynamoDB table, `productId` as the partition key, a GSI on `category` for catalog browsing. No capacity planning, scales to zero cost when idle — appropriate for a catalog that's read far more than it's written and doesn't need joins.
- **Cart**: `PAY_PER_REQUEST` DynamoDB table, `userId` partition key + `productId` sort key, with DynamoDB TTL on an `expiresAt` attribute so abandoned carts clean themselves up instead of needing a scheduled job.
- **Orders**: RDS Postgres, single-AZ. Orders need relational integrity (an order references a user and one or more line items, and status changes need to be queryable and auditable) and ad hoc analytical queries that are awkward on DynamoDB's key-value model without maintaining extra GSIs for every access pattern. A small, single-AZ Postgres instance is cheap enough for a portfolio workload and demonstrates working with a relational engine, which the target roles expect alongside NoSQL experience.

## Consequences
- Two different data stores means two different backup/restore and IAM models to manage — more moving parts than an all-RDS or all-DynamoDB design, but that's a deliberate demonstration of picking the right tool per access pattern rather than defaulting to one database for everything.
- Cross-domain consistency (e.g., an order referencing a product that lives in DynamoDB) is handled at the application layer, not by a foreign key — the Order service calls the Product service/table to validate rather than relying on DB-level referential integrity. Worth calling out as a trade-off in interviews: this is the standard cost of polyglot persistence.
- If product catalog queries ever needed complex filtering (price ranges + category + in-stock, sorted several ways), DynamoDB's GSI model would start to strain and RDS or a search index (e.g. OpenSearch) would be the next reach — noted here as the "what I'd do differently at scale" answer for this decision.
