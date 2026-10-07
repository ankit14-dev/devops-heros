# AWS IAM – Identity and Access Management (Governance)

**Author:** Ankit Kumar

## What is IAM?

AWS Identity and Access Management (IAM) is the global AWS service that controls **who** (authentication) can do **what** (authorization) on **which** AWS resources. Every AWS API call, whether it comes from the console, the CLI, an SDK or Terraform, is checked against IAM before it runs.

Key facts:

- IAM is **global**: users, groups, roles and policies are not tied to a region.
- IAM is **free**. You pay only for the resources the identities use.
- By default an identity can do **nothing**. Every permission has to be granted explicitly.

## Core building blocks

| Concept | What it is | Credentials | Typical use |
|---------|------------|-------------|-------------|
| **Root user** | The identity created with the account (email address) | Password (+ MFA) | Only for a few account-level tasks such as closing the account or changing the support plan |
| **User** | A long-lived identity for one person or one application | Password and/or access keys | Legacy setups, break-glass access |
| **Group** | A collection of users. Policies attached to the group apply to every member | None (groups cannot log in) | `Developers`, `Admins`, `ReadOnly` |
| **Role** | An identity with **no long-lived credentials**, assumed by a trusted principal | Temporary credentials from AWS STS | EC2/Lambda/ECS workloads, CI/CD, cross-account access, SSO |
| **Policy** | A JSON document that defines permissions | n/a | Attached to users, groups, roles or resources |

### Users

An IAM user is a permanent identity. It can have a console password, up to two access keys (`AKIA...`) for programmatic access, and MFA devices. Because access keys never expire on their own, they are the most common source of leaked credentials.

### Groups

Groups make permission management scale. Instead of attaching the same policy to 20 users, I attach it once to a group. A user can belong to multiple groups, but groups **cannot be nested** and a group is not a principal (it cannot appear in a resource policy).

### Roles

A role has two policies:

1. **Trust policy**: *who* may assume the role (a service, an account, an OIDC/SAML provider).
2. **Permissions policy**: *what* the role may do once assumed.

When a principal calls `sts:AssumeRole`, STS returns temporary credentials (access key, secret key and session token) that expire after 15 minutes to 12 hours, depending on the role's maximum session duration.

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/ReadOnlyAuditor \
  --role-session-name ankit-audit
aws sts get-caller-identity   # shows which identity the CLI is using
```

<!-- REAL-OUTPUT: aws sts get-caller-identity output (account ID masked) -->

## Policies

A policy is a JSON document made of one or more **statements**:

| Element | Meaning |
|---------|---------|
| `Version` | Policy language version. Always `"2012-10-17"` |
| `Sid` | Optional statement ID |
| `Effect` | `Allow` or `Deny` |
| `Action` | API operations, e.g. `s3:GetObject`, `ec2:*` |
| `Resource` | ARNs the statement applies to |
| `Condition` | Optional extra checks (IP, MFA, tags, region, time...) |
| `Principal` | Only in resource-based and trust policies: who the statement applies to |

Example: allow reading one bucket, but only over TLS and only from the `ap-south-1` region:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadAppBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::ankit-app-data",
        "arn:aws:s3:::ankit-app-data/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "true" },
        "StringEquals": { "aws:RequestedRegion": "ap-south-1" }
      }
    }
  ]
}
```

Note that `s3:ListBucket` applies to the bucket ARN while `s3:GetObject` applies to the object ARN (`/*`). Mixing these up is a classic mistake.

### Types of policies

- **AWS managed**: written and maintained by AWS (e.g. `ReadOnlyAccess`). Easy, but usually broader than needed.
- **Customer managed**: written by me, reusable, versioned (up to 5 versions).
- **Inline**: embedded directly in a single user/group/role. Deleted together with it.

## Permissions

### Identity-based vs resource-based

| | Identity-based policy | Resource-based policy |
|---|---|---|
| Attached to | User, group or role | A resource (S3 bucket, SQS queue, KMS key, Lambda function...) |
| Has `Principal`? | No (the principal is whoever it is attached to) | Yes |
| Cross-account | Needs a matching resource policy or role trust on the other side | Can directly grant access to another account |
| Example | "Developers may start EC2 instances" | "Account 222222222222 may read this bucket" |

A role's **trust policy** is itself a resource-based policy (the resource is the role).

### Policy evaluation logic

When a request arrives, AWS evaluates all applicable policies (SCPs, resource policies, identity policies, permission boundaries, session policies):

```
1. Start with an implicit DENY (everything is denied by default)
2. Is there an explicit "Deny" in ANY applicable policy?   -> DENY (final)
3. Do SCPs / RCPs / permission boundaries / session policies allow it? (if present)  -> if not, DENY
4. Is there an "Allow" in an identity-based OR resource-based policy?  -> ALLOW
5. Otherwise                                                           -> implicit DENY
```

The rule to remember: **an explicit Deny always wins**, and **no Allow means Deny**. For cross-account requests, both sides must allow: the caller's identity policy *and* the resource policy (or role trust) in the target account.

I can test this without touching real resources using the policy simulator:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/app-s3-reader \
  --action-names s3:GetObject s3:PutObject \
  --resource-arns arn:aws:s3:::ankit-app-data/report.csv
```

<!-- REAL-OUTPUT: policy simulator result showing GetObject allowed and PutObject implicitDeny -->

## Least privilege

Least privilege means granting **only the actions, on only the resources, under only the conditions** a task really needs. In practice:

- Start from nothing and add permissions; don't start from `*:*` and remove.
- Scope `Resource` to specific ARNs instead of `"*"` whenever the service supports it.
- Use `Condition` keys (source VPC, tags, MFA) to narrow further.
- Use **IAM Access Analyzer** policy generation (from CloudTrail activity) and "last accessed" data to remove unused permissions.
- Use **permission boundaries** to cap what a delegated admin can grant.

## IAM best practices

| Practice | Why |
|----------|-----|
| Enable **MFA on the root user** and lock it away | Root cannot be restricted by IAM policies |
| **Never create root access keys** (delete any that exist) | A leaked root key is full account takeover |
| Prefer **roles and temporary credentials** over long-lived access keys | Credentials expire automatically |
| Use **IAM Identity Center** (successor to AWS SSO) for human access | Central users, permission sets, short-lived sessions across many accounts |
| Use **OIDC federation** for CI/CD instead of storing keys in secrets | No static secret to leak |
| **Rotate** any access keys that must exist, and remove unused ones | Limits the blast radius of a leak |
| Use **IAM Access Analyzer** | Finds resources shared outside the account, unused access, and validates policies |
| Enforce a strong **password policy** and MFA for all humans | Basic account hygiene |
| Use **groups** (or permission sets), not per-user policies | Easier to audit |
| Enable **CloudTrail** | Audit log of every API call |
| Use **SCPs** in AWS Organizations as guardrails | e.g. deny leaving the org or disabling CloudTrail |

## Common use cases

### 1. EC2 instance role for S3

An application on EC2 needs to read from S3. Instead of copying access keys onto the server, I create a role with a trust policy for `ec2.amazonaws.com`, wrap it in an **instance profile**, and attach it to the instance. The SDK picks up temporary credentials automatically from the instance metadata service (IMDSv2).

### 2. GitHub Actions with OIDC

GitHub Actions can exchange its OIDC token for AWS credentials. The trust policy restricts which repo and branch may assume the role:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:ankit14-dev/devops-heros:ref:refs/heads/main" }
  }
}
```

In the workflow, `aws-actions/configure-aws-credentials` with `role-to-assume` and `permissions: id-token: write` does the exchange. No AWS secrets are stored in GitHub.

### 3. Cross-account access

Account B (prod) creates a role whose trust policy allows account A (tooling) to assume it, ideally with an `sts:ExternalId` or MFA condition. Users in account A also need `sts:AssumeRole` on that role ARN in their own identity policy.

## Terraform: least-privilege S3 read-only role

```hcl
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_s3_reader" {
  name               = "app-s3-reader"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

data "aws_iam_policy_document" "s3_read_only" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::ankit-app-data"]
  }
  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::ankit-app-data/*"]
  }
}

resource "aws_iam_policy" "s3_read_only" {
  name   = "ankit-app-data-read-only"
  policy = data.aws_iam_policy_document.s3_read_only.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.app_s3_reader.name
  policy_arn = aws_iam_policy.s3_read_only.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "app-s3-reader"
  role = aws_iam_role.app_s3_reader.name
}
```

Using `aws_iam_policy_document` instead of raw JSON strings gives me validation at plan time and avoids quoting errors.

<!-- REAL-OUTPUT: terraform plan output for the IAM role/policy -->

## What I learned

- Authentication and authorization are separate: IAM answers both, but policies only deal with authorization.
- Roles + STS are the right default for both workloads and humans; long-lived access keys are the exception.
- Explicit `Deny` beats everything, and "no matching Allow" is also a deny, which explains most `AccessDenied` errors I hit.
- Bucket-level vs object-level ARNs matter for S3 permissions.
