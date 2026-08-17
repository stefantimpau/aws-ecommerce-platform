# ADR 0003: Reuse an existing subdomain, don't buy a new domain

## Status
Accepted.

## Context
Build step 12 calls for a Route 53 hosted zone and ACM certificate for the demo storefront's custom domain. The two options were: register a brand-new domain dedicated to this project, or use a subdomain of a domain already owned and already managed in Route 53 (`stefantimpau.com`, used for the portfolio site).

This project is also explicitly short-lived — it gets built, documented with screenshots, pushed to GitHub, and torn down, not run indefinitely.

## Decision
Use `shop.stefantimpau.com` (frontend) and `api.shop.stefantimpau.com` (API Gateway) as subdomains of the existing `stefantimpau.com` zone, looked up via a Terraform data source rather than created as a new resource. No new domain is purchased.

## Consequences
- No recurring registration cost for a domain that's only in active use for a few days.
- No separate DNS zone to create, delegate, or later delete — one less moving part in both the build and the teardown script.
- The Terraform still fully exercises the skill the build order is testing (ACM DNS validation, Route 53 record management, CloudFront/API Gateway custom domains) — a second top-level domain wouldn't have demonstrated anything additional technically.
- Slight trade-off: this couples the demo's DNS lifecycle to the portfolio site's zone. The teardown script needs to remove exactly the records/certs this project created and nothing belonging to the main site — worth being deliberate about scoping teardown by resource, not by "empty the whole zone."
