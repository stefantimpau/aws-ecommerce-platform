# ADR 0004: The CI/CD deploy role gets scoped permissions, not full `terraform apply`

## Status
Accepted.

## Context
Build step 22 (stretch goal) adds GitHub Actions so a code change can be built, pushed, and deployed without a human running scripts by hand from a laptop. The natural-looking design is one workflow, triggered on push to `main`, that authenticates to AWS and runs `terraform apply` against the full `terraform/environments/dev` config — the same thing a human would type locally.

The problem: that config manages everything from the VPC and RDS instance to WAF Web ACLs and Route 53 records. Granting a GitHub Actions role permission to apply it in full means granting that role something close to account-level admin access over this project's resources — every IAM role, every security group, every piece of data storage — reachable from anywhere a workflow file (or a compromised dependency inside one) can trigger it. That's a much larger blast radius than "ship a new container image" needs, and it sits awkwardly next to the rest of this project's IAM design, where every ECS task role is deliberately scoped to touch only the one table or topic that service actually needs (Product can't touch Orders, Order can't touch Cognito, and so on).

## Decision
Split "infrastructure changes" from "application deploys" by permission level, not just by workflow file:

- **Infrastructure** (VPC, RDS, ALB, WAF, DNS, IAM roles, anything structural) is still applied by a human, locally, with their own broader AWS credentials — exactly as it has been for the whole build. CI never touches this.
- **Application deploys** (a new image for one or more of the four services, plus the frontend build) go through `.github/workflows/deploy.yml`, which assumes an IAM role via GitHub OIDC (no long-lived access keys stored as a repo secret) scoped to exactly: push to the four ECR repos, register a new ECS task-definition revision and update the four ECS services, read/write this project's Terraform state object, and sync the frontend S3 bucket plus invalidate its CloudFront distribution. The `terraform apply` this workflow runs is deliberately `-target=module.ecs` — it can change the ECS task definitions and services, and nothing else in the state.

## Consequences
- The deploy role's IAM policy can be fully enumerated and justified line by line (`terraform/modules/github-oidc/main.tf`) — there's no "just in case" wildcard access anywhere in it.
- A compromised or buggy workflow run can, at worst, push a bad container image and roll it out — it cannot touch the database, networking, WAF rules, or DNS. That containment boundary is the whole point.
- The trade-off: this isn't "real" continuous deployment of infrastructure changes — a Terraform change to, say, the ALB's listener rules still requires a human to run `apply` locally. For a portfolio project built and torn down by one operator, that's the right shape; a team running this in production long-term would eventually want a properly permissioned infra pipeline too (likely with a manual-approval gate rather than a wide-open role), not just an app-deploy one.
- `-target` is normally something to avoid in Terraform (it can let config and state drift apart if used carelessly) — it's safe here specifically because `module.ecs`'s only externally-changing input from this workflow is `image_tag`, and nothing else in the config depends on the *output* of that module in a way that would need reconciling. A wider `-target` blast radius would be a reason to reconsider this pattern.
