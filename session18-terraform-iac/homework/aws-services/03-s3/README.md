# Amazon S3 – Simple Storage Service

**Author:** Ankit Kumar

## What is S3?

Amazon S3 is AWS's **object storage** service. Instead of files in a directory tree (file storage) or blocks on a disk (block storage like EBS), S3 stores **objects** in **buckets** and accesses them over an HTTPS API.

- Designed for **99.999999999% (11 nines) durability**: data is stored redundantly across at least 3 AZs (except One Zone classes).
- Virtually unlimited capacity; pay for storage used, requests and data transfer out.
- **Strong read-after-write consistency** for all PUT and DELETE operations (since December 2020).

## Buckets

A bucket is the top-level container for objects.

- Bucket names are **globally unique** across all AWS accounts (within a partition), 3–63 characters, lowercase letters, numbers, dots and hyphens.
- A bucket is created in **one region**; the data stays in that region unless I replicate it (CRR/SRR).
- Default soft limit is 10,000 buckets per account (it used to be 100).
- Since April 2023, new buckets have **Block Public Access ON** and **ACLs disabled** (Object Ownership = bucket owner enforced) by default.

```bash
aws s3 mb s3://ankit-devops-heros-demo --region ap-south-1
aws s3 ls
```

## Objects

An object consists of:

| Part | Description |
|------|-------------|
| **Key** | The full name, e.g. `logs/2026/10/app.log`. S3 is flat; the `/` "folders" are just key prefixes |
| **Value** | The data, from 0 bytes up to **5 TB** |
| **Version ID** | Present when versioning is enabled |
| **Metadata** | System metadata (`Content-Type`, `Last-Modified`, `ETag`) and user metadata (`x-amz-meta-*`) |
| **Tags** | Up to 10 key-value tags, usable in lifecycle rules and IAM conditions |

A single `PUT` can upload up to **5 GB**; anything bigger must use **multipart upload** (recommended from ~100 MB). The `aws s3 cp` command does multipart automatically.

```bash
aws s3 cp ./report.csv s3://ankit-devops-heros-demo/reports/report.csv
aws s3 ls s3://ankit-devops-heros-demo/reports/
aws s3 presign s3://ankit-devops-heros-demo/reports/report.csv --expires-in 3600
```

## Storage classes

| Class | AZs | Min. storage duration | Retrieval | Typical use |
|-------|-----|----------------------|-----------|-------------|
| **S3 Standard** | ≥3 | None | Milliseconds | Frequently accessed data |
| **S3 Intelligent-Tiering** | ≥3 | None | Milliseconds (archive tiers optional) | Unknown or changing access patterns; small monitoring fee per object |
| **S3 Standard-IA** | ≥3 | 30 days | Milliseconds, per-GB retrieval fee | Infrequent but fast access (backups) |
| **S3 One Zone-IA** | 1 | 30 days | Milliseconds, per-GB retrieval fee | Re-creatable infrequent data |
| **S3 Glacier Instant Retrieval** | ≥3 | 90 days | Milliseconds | Archive accessed about once a quarter |
| **S3 Glacier Flexible Retrieval** | ≥3 | 90 days | Minutes to 12 hours (expedited / standard / bulk) | Archives, rarely restored |
| **S3 Glacier Deep Archive** | ≥3 | 180 days | Within 12 hours (bulk up to 48 h) | Compliance data kept for years, cheapest |

There is also **S3 Express One Zone** for single-digit-millisecond latency in a single AZ (directory buckets), mainly for ML and analytics workloads. The IA and Glacier Instant classes bill a minimum object size of 128 KB.

## Versioning

Versioning keeps every version of an object in the bucket.

- States: *Unversioned* (default) → *Enabled* → *Suspended*. Once enabled it can never go back to unversioned.
- Deleting an object without a version ID only adds a **delete marker**; older versions are still there and recoverable.
- Protects against accidental overwrites and deletes. It is required for **replication** and **Object Lock**.
- Every version is billed, so versioning is normally combined with a lifecycle rule for noncurrent versions.

```bash
aws s3api put-bucket-versioning --bucket ankit-devops-heros-demo \
  --versioning-configuration Status=Enabled
aws s3api list-object-versions --bucket ankit-devops-heros-demo --prefix reports/
```

## Lifecycle policies

Lifecycle rules automatically **transition** objects to cheaper classes or **expire** (delete) them.

```json
{
  "Rules": [
    {
      "ID": "logs-tiering",
      "Status": "Enabled",
      "Filter": { "Prefix": "logs/" },
      "Transitions": [
        { "Days": 30,  "StorageClass": "STANDARD_IA" },
        { "Days": 90,  "StorageClass": "GLACIER" },
        { "Days": 365, "StorageClass": "DEEP_ARCHIVE" }
      ],
      "Expiration": { "Days": 2555 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration --bucket ankit-devops-heros-demo \
  --lifecycle-configuration file://lifecycle.json
```

(`GLACIER` is the API name for Glacier Flexible Retrieval; `GLACIER_IR` is Glacier Instant Retrieval.)

## Encryption

| Option | Who manages keys | Notes |
|--------|------------------|-------|
| **SSE-S3** | S3 (AES-256) | **Default for all new objects since January 2023**, no cost, no setup |
| **SSE-KMS** | AWS KMS (AWS managed or customer managed key) | Key policies, CloudTrail audit of key use; enable **S3 Bucket Keys** to reduce KMS request cost |
| **DSSE-KMS** | AWS KMS | Dual-layer server-side encryption, for compliance rules that require two layers |
| **SSE-C** | Customer provides key with each request | S3 never stores the key |
| **Client-side** | Application encrypts before upload | e.g. AWS Encryption SDK; S3 only sees ciphertext |

**In transit**: S3 endpoints support TLS. To *enforce* it, add a bucket policy that denies requests where `aws:SecureTransport` is `false` (see below).

## Bucket policies and Block Public Access

A bucket policy is a **resource-based** IAM policy attached to the bucket. Example: deny non-TLS access, and allow a role from another account to read objects:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::ankit-devops-heros-demo",
        "arn:aws:s3:::ankit-devops-heros-demo/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "AllowPartnerRead",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::222222222222:role/reporting" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::ankit-devops-heros-demo/reports/*"
    }
  ]
}
```

**Block Public Access (BPA)** is a safety switch at the account and bucket level with four settings:

| Setting | Effect |
|---------|--------|
| `BlockPublicAcls` | Rejects new public ACLs |
| `IgnorePublicAcls` | Ignores any existing public ACLs |
| `BlockPublicPolicy` | Rejects bucket policies that grant public access |
| `RestrictPublicBuckets` | Limits access to buckets with public policies to AWS principals and the account |

BPA overrides bucket policies and ACLs, so a bucket stays private even if someone writes a public policy by mistake. I keep all four ON unless a bucket really has to be public.

## Common use cases

1. **Static website hosting**: HTML/CSS/JS in a bucket. The recommended setup is a private bucket served through **CloudFront with Origin Access Control (OAC)** and HTTPS, rather than a public website endpoint.
2. **Backups and archives**: database dumps, EBS/RDS exports, with lifecycle rules into Glacier.
3. **Data lake**: raw and processed data in open formats (Parquet), queried with Athena, Glue, EMR or Redshift Spectrum.
4. **Terraform remote state**: shared, versioned state for a team.
5. Artifact storage for CI/CD, log storage (ALB, CloudTrail, VPC Flow Logs), media hosting.

### Terraform remote state backend

```hcl
terraform {
  backend "s3" {
    bucket       = "ankit-terraform-state"
    key          = "session18/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true # S3-native state locking (Terraform >= 1.10)
  }
}
```

Older setups used a DynamoDB table (`dynamodb_table = "..."`) for locking; with Terraform 1.10+ the S3 lock file replaces it. The state bucket should have versioning on so a broken state can be rolled back.

### Terraform bucket with secure defaults

```hcl
resource "aws_s3_bucket" "demo" {
  bucket = "ankit-devops-heros-demo"
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
```

<!-- REAL-OUTPUT: terraform apply / aws s3 ls output from the terraform-s3-demo -->

## What I learned

- S3 is flat key-value storage; "folders" are only prefixes.
- Choosing a storage class is a trade-off between storage price, retrieval price/latency and minimum duration.
- Versioning + lifecycle rules + Block Public Access + default encryption are the baseline for any bucket I create.
- Terraform state belongs in a versioned, encrypted, private S3 bucket with locking.
