# Amazon VPC – Virtual Private Cloud

**Author:** Ankit Kumar

## What is a VPC?

A VPC is a **logically isolated private network** inside an AWS region. I choose its IP range, split it into subnets, and control routing and firewalls. Resources such as EC2, RDS, Lambda (in VPC mode) and load balancers are launched into it.

- A VPC is **regional** and spans all AZs in the region.
- A **subnet** lives in exactly **one AZ**.
- Every account has a **default VPC** per region (`172.31.0.0/16`, one public subnet per AZ). For real projects I create a custom VPC.

## CIDR

CIDR (Classless Inter-Domain Routing) notation describes an IP range as `address/prefix`. The prefix is the number of fixed network bits; the remaining `32 - prefix` bits are for hosts.

```
number of addresses = 2^(32 - prefix)
```

| CIDR | Host bits | Addresses | Usable in an AWS subnet (−5) |
|------|-----------|-----------|------------------------------|
| `10.0.0.0/16` | 16 | 2^16 = **65,536** | (VPC range, not a subnet) |
| `10.0.0.0/20` | 12 | 4,096 | 4,091 |
| `10.0.1.0/24` | 8 | 256 | **251** |
| `10.0.1.0/28` | 4 | 16 | 11 |

Rules:

- VPC CIDR size must be between **/16** (65,536) and **/28** (16). Secondary CIDRs can be added later.
- Use private (RFC 1918) ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- Plan ranges so they **don't overlap** with on-prem networks or other VPCs you may peer with.

### The 5 reserved addresses

In every subnet AWS reserves the first four and the last address. For `10.0.1.0/24`:

| Address | Purpose |
|---------|---------|
| `10.0.1.0` | Network address |
| `10.0.1.1` | VPC router |
| `10.0.1.2` | Amazon-provided DNS (VPC base + 2) |
| `10.0.1.3` | Reserved for future use |
| `10.0.1.255` | Network broadcast (broadcast isn't supported, but the address is reserved) |

So a /24 gives 256 − 5 = **251** usable IPs.

## Subnets

A subnet is a slice of the VPC CIDR in one AZ. Whether it is "public" or "private" is not a checkbox: it depends on its **route table**.

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 create-subnet --vpc-id vpc-0abc --cidr-block 10.0.1.0/24 --availability-zone ap-south-1a
```

## Route tables

A route table is a set of rules (routes) that decide where traffic from a subnet goes.

- Every route table has a `local` route for the VPC CIDR that cannot be removed: all subnets in a VPC can reach each other.
- Each subnet is associated with **exactly one** route table (the **main** route table if not set explicitly).
- The most specific route (longest prefix) wins.

| Destination | Target | Meaning |
|-------------|--------|---------|
| `10.0.0.0/16` | `local` | Traffic inside the VPC |
| `0.0.0.0/0` | `igw-xxxx` | Everything else to the internet (public subnet) |
| `0.0.0.0/0` | `nat-xxxx` | Everything else via NAT (private subnet) |

## Internet Gateway (IGW)

- Horizontally scaled, redundant, no bandwidth limit, **free**.
- One IGW per VPC.
- Performs 1:1 NAT between an instance's private IP and its public IPv4 address.
- An instance can talk to the internet only if: the subnet routes `0.0.0.0/0` to the IGW, **and** the instance has a public IP/Elastic IP, **and** SG/NACL rules allow it.

## NAT Gateway

A NAT Gateway lets instances in **private** subnets start **outbound** connections (OS updates, calling external APIs) while blocking connections initiated from the internet.

- Placed in a **public** subnet, with an Elastic IP (public NAT).
- It is **zonal**: for high availability create one NAT Gateway per AZ and route each private subnet to the NAT in its own AZ.
- Charged per hour **and** per GB processed, so it's often the most surprising line on a student AWS bill.
- For IPv6, an **egress-only internet gateway** does the same job.
- For AWS services such as S3 and DynamoDB, a **gateway VPC endpoint** avoids NAT charges.

## Security Groups and Network ACLs

**Security groups** act at the instance (ENI) level; **network ACLs** act at the subnet boundary.

| | Security Group | Network ACL |
|---|---|---|
| Level | Instance / ENI | Subnet |
| State | **Stateful** (return traffic auto-allowed) | **Stateless** (return traffic must be allowed explicitly, e.g. ephemeral ports 1024–65535) |
| Rule types | **Allow only** | **Allow and Deny** |
| Rule evaluation | All rules evaluated together | Rules evaluated **in number order**, lowest first; first match wins |
| Default | Inbound denied, outbound allowed | Default NACL allows all; a **custom** NACL denies all until rules are added |
| Can reference other SGs | Yes | No, CIDR only |
| Typical use | Main firewall for each app tier | Coarse subnet-wide blocks (e.g. deny a malicious IP range) |

Example NACL inbound rules for a public web subnet:

| Rule # | Type | Port | Source | Action |
|--------|------|------|--------|--------|
| 90 | All | All | 198.51.100.0/24 | DENY |
| 100 | TCP | 443 | 0.0.0.0/0 | ALLOW |
| 110 | TCP | 1024–65535 | 0.0.0.0/0 | ALLOW (return traffic) |
| * | All | All | 0.0.0.0/0 | DENY |

## Public vs private subnet

| | Public subnet | Private subnet |
|---|---|---|
| Route `0.0.0.0/0` to | Internet Gateway | NAT Gateway (or nothing) |
| Instances get public IPs | Usually yes | No |
| Reachable from the internet | Yes (if SG allows) | No |
| Typical resources | ALB, NAT Gateway, bastion | App servers, RDS, caches, EKS nodes |

## Architecture: 2-AZ VPC

```
                                 Internet
                                    |
                          +---------+---------+
                          | Internet Gateway  |
                          +---------+---------+
 VPC 10.0.0.0/16                    |
+-----------------------------------+-----------------------------------+
|        AZ a (ap-south-1a)         |        AZ b (ap-south-1b)         |
|  +-----------------------------+  |  +-----------------------------+  |
|  | Public subnet  10.0.1.0/24  |  |  | Public subnet  10.0.2.0/24  |  |
|  |  [ALB node]    [NAT GW a]   |  |  |  [ALB node]    [NAT GW b]   |  |
|  +--------------+--------------+  |  +--------------+--------------+  |
|                 ^ outbound via    |                 ^ outbound via    |
|                 | NAT a           |                 | NAT b           |
|  +--------------+--------------+  |  +--------------+--------------+  |
|  | Private subnet 10.0.11.0/24 |  |  | Private subnet 10.0.12.0/24 |  |
|  |  [App EC2]  [RDS primary]   |  |  |  [App EC2]  [RDS standby]   |  |
|  +-----------------------------+  |  +-----------------------------+  |
+-----------------------------------+-----------------------------------+
 Public RT:     10.0.0.0/16 -> local, 0.0.0.0/0 -> igw
 Private RT a:  10.0.0.0/16 -> local, 0.0.0.0/0 -> nat-a
 Private RT b:  10.0.0.0/16 -> local, 0.0.0.0/0 -> nat-b
```

## Terraform snippet

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "ankit-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 1) # 10.0.1.0/24
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
```

`cidrsubnet("10.0.0.0/16", 8, 1)` adds 8 bits to the prefix (/16 → /24) and picks network number 1, giving `10.0.1.0/24`.

<!-- REAL-OUTPUT: terraform console cidrsubnet results / aws ec2 describe-subnets output -->

## What I learned

- "Public subnet" just means "its route table has a route to an IGW".
- CIDR math is simple powers of two, but AWS always takes 5 addresses per subnet.
- NAT Gateways are per-AZ and cost money per hour and per GB; VPC endpoints are a cheaper path to S3/DynamoDB.
- Security groups (stateful, allow-only) do most of the work; NACLs are an extra stateless layer.
