# Amazon DynamoDB and Amazon RDS – Databases on AWS

**Author:** Ankit Kumar

AWS offers many managed databases. This page covers the two I'm most likely to use first: **DynamoDB** (NoSQL, serverless) and **RDS** (managed relational databases).

---

## Part 1 – Amazon DynamoDB

### NoSQL

DynamoDB is a fully managed, serverless **NoSQL key-value and document database**. There are no servers to patch and no storage to size. It delivers single-digit-millisecond latency at almost any scale.

- No fixed schema: only the primary key is defined up front. Every item can have different attributes.
- No joins. You design tables around **access patterns** (the queries the app will run), not around normalized entities.
- Data is replicated across 3 AZs in a region. **Global tables** add multi-region, multi-active replication.

### Tables, items and attributes

| Term | Relational equivalent | Notes |
|------|----------------------|-------|
| **Table** | Table | Collection of items |
| **Item** | Row | Max size **400 KB** |
| **Attribute** | Column | Scalar (String, Number, Binary, Boolean, Null), document (List, Map) or set types |

### Partition key and sort key

The **primary key** is either:

1. **Partition key only** (simple primary key): it must be unique for every item.
2. **Partition key + sort key** (composite primary key): the combination must be unique.

DynamoDB hashes the partition key to decide which physical partition stores the item. A high-cardinality partition key spreads load evenly; a low-cardinality one (e.g. `status`) creates **hot partitions**. Items with the same partition key are stored together, ordered by the sort key, so range queries (`begins_with`, `between`, `>`) on the sort key are fast.

Example `Orders` table (partition key `CustomerId`, sort key `OrderDate`):

| CustomerId (PK) | OrderDate (SK) | OrderId | Total | Status |
|-----------------|----------------|---------|-------|--------|
| `C#1001` | `2026-09-01` | `O-501` | 1200 | `SHIPPED` |
| `C#1001` | `2026-09-15` | `O-517` | 450 | `PENDING` |
| `C#1002` | `2026-09-03` | `O-503` | 89 | `DELIVERED` |

"All orders of customer C#1001 in September 2026" becomes a single efficient `Query`:

```bash
aws dynamodb query --table-name Orders \
  --key-condition-expression "CustomerId = :c AND begins_with(OrderDate, :m)" \
  --expression-attribute-values '{":c":{"S":"C#1001"},":m":{"S":"2026-09"}}'
```

`Query` reads one partition. `Scan` reads the whole table, so I avoid it for anything except small tables or exports.

### Capacity modes

| Mode | How it works | Good for |
|------|--------------|----------|
| **On-demand** | Pay per read/write request, scales automatically | Unpredictable or spiky traffic, new apps, dev/test |
| **Provisioned** | Set RCUs/WCUs (optionally with auto scaling); throttled if exceeded | Steady, predictable traffic; cheaper at sustained load |

1 RCU = one strongly consistent read per second of up to 4 KB (or two eventually consistent reads). 1 WCU = one write per second of up to 1 KB.

### Secondary indexes (GSI / LSI)

| | Global Secondary Index (GSI) | Local Secondary Index (LSI) |
|---|---|---|
| Key | Different partition key and optional sort key | Same partition key, different sort key |
| When created | Any time | **Only at table creation** |
| Read consistency | Eventually consistent only | Eventual or strong |
| Default limit | 20 per table | 5 per table |
| Capacity | Its own (in provisioned mode) | Shares the table's |

Example: a GSI on `Status` + `OrderDate` lets me list all `PENDING` orders without scanning.

Other features: **TTL** (expire items automatically), **DynamoDB Streams** (change data capture to Lambda), **PITR** (continuous backups, 35 days), **transactions**, and **DAX** (in-memory cache).

### DynamoDB use cases

- Session stores, shopping carts and user profiles.
- Gaming leaderboards, IoT device data, event/clickstream data.
- Serverless backends with API Gateway + Lambda.
- Any key-based lookup that has to stay fast at very large scale.

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "Orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CustomerId"
  range_key    = "OrderDate"

  attribute {
    name = "CustomerId"
    type = "S"
  }
  attribute {
    name = "OrderDate"
    type = "S"
  }

  point_in_time_recovery { enabled = true }
}
```

---

## Part 2 – Amazon RDS

### Relational database

Amazon RDS (Relational Database Service) runs a **managed relational (SQL) database**. AWS handles provisioning, OS and engine patching, backups, failover and monitoring. I still own the schema, queries, indexes, users and parameter tuning. Data lives in tables with a fixed schema, relationships via foreign keys, joins and ACID transactions.

### Supported engines

| Engine | Notes |
|--------|-------|
| **Amazon Aurora** | AWS-built, MySQL- and PostgreSQL-compatible; distributed storage with 6 copies across 3 AZs; Aurora Serverless v2 |
| **MySQL** | Open source |
| **PostgreSQL** | Open source |
| **MariaDB** | Open source MySQL fork |
| **Oracle** | License included or Bring Your Own License |
| **Microsoft SQL Server** | Express, Web, Standard, Enterprise editions |
| **IBM Db2** | Added in late 2023 |

### DB instances

A **DB instance** is an isolated database environment running one engine. Its main settings:

- **Instance class**: e.g. `db.t4g.micro` (burstable), `db.m7g.large` (general purpose), `db.r7g.xlarge` (memory optimized).
- **Storage**: gp3, io1/io2 (provisioned IOPS); **storage autoscaling** can grow it automatically.
- **DB subnet group**: the subnets (in at least 2 AZs) the instance can be placed in, normally private ones.
- **Parameter group** (engine settings) and **option group** (extra features).
- **Endpoint**: a DNS name such as `mydb.xxxx.ap-south-1.rds.amazonaws.com`. Apps connect through it, never through an IP.

### Security

| Layer | How |
|-------|-----|
| **Network** | Launch in **private subnets** of a VPC; set `PubliclyAccessible = false`; the security group allows the DB port (3306/5432) only from the app tier's SG |
| **Encryption at rest** | **KMS**, enabled at creation. It covers storage, automated backups, snapshots and read replicas. An existing unencrypted DB can't be encrypted in place: snapshot → copy with encryption → restore |
| **Encryption in transit** | TLS; can be enforced (e.g. `rds.force_ssl=1` for PostgreSQL) |
| **Authentication** | Database users/passwords, or **IAM database authentication** (MySQL, MariaDB, PostgreSQL) with short-lived tokens |
| **Secrets** | **Secrets Manager** integration: RDS can create and rotate the master password (`manage_master_user_password`) |
| **Auditing** | CloudTrail for API calls, engine logs exported to CloudWatch Logs |

### Backups

- **Automated backups**: a daily snapshot during the backup window plus transaction logs. Retention is **0–35 days**; setting 0 disables them.
- **Point-in-time recovery (PITR)**: restore to any second inside the retention period, typically up to about the last 5 minutes. A restore always creates a **new** DB instance with a new endpoint.
- **Manual snapshots**: user-initiated, kept **until I delete them** (even after the DB is deleted). They can be copied to other regions or shared with other accounts.
- **AWS Backup** can manage RDS backups centrally with backup plans.

### Multi-AZ and read replicas

**Multi-AZ** keeps a **synchronous standby** in another AZ. If the primary fails (or during patching), RDS flips the endpoint's DNS to the standby, usually within 1–2 minutes. In the classic deployment the standby **cannot serve reads**. A newer **Multi-AZ DB cluster** option (MySQL/PostgreSQL) has two readable standbys.

**Read replicas** use **asynchronous** replication to offload read traffic. A replica can live in another region and can be promoted to a standalone database.

| | Multi-AZ (instance) | Read replica |
|---|---|---|
| Main purpose | **High availability** / durability | **Read scaling** |
| Replication | Synchronous | Asynchronous (replica lag possible) |
| Serves reads? | No (standby is passive) | Yes |
| Location | Same region, different AZ | Same AZ, cross-AZ or **cross-region** |
| Failover | Automatic, same endpoint | Manual promotion, new endpoint |
| Count | 1 standby | Up to 15 (MySQL, MariaDB, PostgreSQL; fewer for some engines) |

They can be combined: a Multi-AZ primary with read replicas, and replicas can be Multi-AZ themselves.

### RDS use cases

- Web and mobile application backends that need SQL, joins and transactions.
- E-commerce orders, payments, inventory and ERP/CRM systems.
- Migrating existing MySQL/PostgreSQL/Oracle/SQL Server databases without managing servers.
- Reporting on structured data (with read replicas).

```hcl
resource "aws_db_instance" "app" {
  identifier                  = "ankit-app-db"
  engine                      = "postgres"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = "appadmin"
  manage_master_user_password = true # password stored and rotated in Secrets Manager
  db_subnet_group_name        = aws_db_subnet_group.private.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  multi_az                    = true
  backup_retention_period     = 7
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "ankit-app-db-final"
}
```

<!-- REAL-OUTPUT: terraform plan / aws rds describe-db-instances or aws dynamodb describe-table output -->

---

## DynamoDB vs RDS

| | DynamoDB | RDS |
|---|---|---|
| Data model | NoSQL key-value / document | Relational (tables, rows, SQL) |
| Schema | Flexible, only the key is fixed | Fixed schema, migrations needed |
| Query language | API (`GetItem`, `Query`, `Scan`), PartiQL | Full SQL with joins and aggregations |
| Transactions | Supported (up to 100 items per transaction) | Full ACID |
| Scaling | Automatic and horizontal, practically unlimited | Vertical (bigger instance) + read replicas; Aurora scales storage automatically |
| Servers | Serverless, nothing to manage | Instances: choose class, storage, maintenance window |
| Performance | Consistent single-digit ms at any scale when keys are well designed | Depends on instance size, indexes and query design |
| HA | Built in (3 AZs), global tables for multi-region | Multi-AZ option, cross-region replicas |
| Pricing | Per request (on-demand) or provisioned capacity + storage | Per instance-hour + storage + I/O (engine-dependent) |
| Best for | Known access patterns, huge scale, simple lookups | Complex queries, reporting, relational integrity, existing SQL apps |

## What I learned

- DynamoDB design starts from the queries. Picking the partition key and sort key is the most important decision.
- RDS takes the operations work away, but I still have to design the schema and tune queries.
- Multi-AZ is for availability, read replicas are for scaling reads. They solve different problems.
- RDS encryption has to be decided at creation time, so I turn it on from day one.
