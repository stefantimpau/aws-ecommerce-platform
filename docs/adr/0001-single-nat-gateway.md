# ADR 0001: Single NAT Gateway instead of one per AZ

## Status
Accepted (default; toggle available via `single_nat_gateway` variable).

## Context
The VPC has two private-app and two private-data subnets across two AZs. Resources in those subnets (ECS tasks pulling images from ECR, hitting SSM/CloudWatch endpoints) need outbound internet access, which requires a NAT Gateway. The standard highly-available pattern is one NAT Gateway per AZ, so a single AZ outage doesn't take down outbound connectivity for the other AZ's private subnets.

Each NAT Gateway costs a fixed hourly charge plus per-GB data processing, independent of traffic. For a portfolio project run intermittently and torn down between sessions, doubling that fixed cost for redundancy that's mostly irrelevant during demo/dev cycles is hard to justify.

## Decision
Default to a single NAT Gateway in AZ 0, with both AZs' private route tables pointing at it. The module (`terraform/modules/vpc`) exposes a `single_nat_gateway` boolean so this can be flipped to one-per-AZ with a single variable change if the project ever needed to demonstrate (or actually run under) a highly-available configuration.

## Consequences
- Lower cost while building/demoing (~50% less NAT spend).
- A failure of the AZ hosting the single NAT Gateway would cut outbound internet access for private subnets in *both* AZs, not just its own — an availability trade-off that would not be acceptable in a real production deployment.
- This trade-off, and the one-line toggle to reverse it, is a deliberate talking point for interviews: it shows the cost-vs-availability decision was made consciously rather than defaulted into.
