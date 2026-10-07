# Amazon EC2 – Elastic Compute Cloud

**Author:** Ankit Kumar

## What is EC2?

Amazon EC2 provides resizable virtual servers (**instances**) in the AWS cloud. It is the classic **IaaS** service: AWS manages the physical hardware, the hypervisor (Nitro) and the data center, and I manage the operating system, patches, runtime and application.

Main properties:

- Instances run in a specific **Availability Zone**, inside a **subnet** of a VPC.
- Pricing options: **On-Demand**, **Savings Plans / Reserved Instances** (1 or 3 year commitment), **Spot** (up to ~90% cheaper, can be interrupted with a 2-minute warning) and **Dedicated Hosts**.
- Scaling out is done with **Auto Scaling groups** behind an **Elastic Load Balancer**.

## AMI (Amazon Machine Image)

An AMI is the template used to launch an instance. It contains:

- A root volume snapshot (OS + preinstalled software).
- Launch permissions (private, shared with accounts, or public).
- Block device mapping (which volumes to attach at launch).

AMIs are **regional**; to use one in another region I copy it (`aws ec2 copy-image`). Sources are AWS-provided (Amazon Linux 2023, Ubuntu, Windows), AWS Marketplace, community AMIs, or my own (built manually or with Packer / EC2 Image Builder).

```bash
# Latest Amazon Linux 2023 AMI ID via the public SSM parameter
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text
```

## Instance types

An instance type name such as **`t3.micro`** breaks down as:

```
t        3          .   micro
family   generation     size
```

Optional letters after the generation describe attributes: `g` = AWS Graviton (ARM), `a` = AMD, `i` = Intel, `d` = local NVMe instance storage, `n` = enhanced networking. Example: `m7g.large` is general purpose, 7th generation, Graviton, size large.

| Family | Category | Characteristics | Example use |
|--------|----------|-----------------|-------------|
| **t** (t3, t4g) | Burstable general purpose | Baseline CPU + CPU credits for bursts | Dev/test, small web servers |
| **m** (m6i, m7g) | General purpose | Balanced CPU : memory (1 vCPU : 4 GiB) | App servers, small databases |
| **c** (c6i, c7g) | Compute optimized | High CPU : memory (1 : 2 GiB) | Batch processing, CI builds, gaming servers |
| **r** (r6i, r7g) | Memory optimized | 1 vCPU : 8 GiB | In-memory caches, large databases |
| **g** (g5, g6) | Accelerated computing (GPU) | NVIDIA GPUs | ML inference, graphics rendering |

Other families exist too: `x` (very high memory), `i` / `d` (storage optimized), `p` (GPU training), `inf` / `trn` (AWS Inferentia / Trainium chips).

Sizes go `nano < micro < small < medium < large < xlarge < 2xlarge ...`; each step roughly doubles vCPU, memory and price.

## Key pairs

A key pair is used for SSH (Linux) or to decrypt the Administrator password (Windows).

- AWS stores the **public key**; I download the **private key** once (`.pem`) and AWS never shows it again.
- Supported types: RSA and ED25519.
- On Linux the public key is placed in `~/.ssh/authorized_keys` of the default user (`ec2-user`, `ubuntu`, ...).

```bash
aws ec2 create-key-pair --key-name ankit-key --key-type ed25519 \
  --query KeyMaterial --output text > ankit-key.pem
chmod 400 ankit-key.pem
ssh -i ankit-key.pem ec2-user@<public-ip>
```

A more secure alternative is **SSM Session Manager**, which needs no open port 22 and no key at all, or **EC2 Instance Connect**, which pushes a short-lived key.

## Security Groups

A security group is a virtual firewall attached to an instance's network interface (ENI).

- **Stateful**: if inbound traffic is allowed, the response is automatically allowed out (and vice versa).
- **Allow rules only**: there is no "deny" rule. Anything not allowed is denied.
- Default: all inbound denied, all outbound allowed.
- Sources can be CIDR blocks, prefix lists or **other security groups** (e.g. "allow 5432 only from the app SG").
- Up to 5 SGs per ENI by default; changes apply immediately.

```bash
aws ec2 authorize-security-group-ingress --group-id sg-0abc123 \
  --protocol tcp --port 22 --cidr 203.0.113.10/32
```

## EBS (Elastic Block Store)

EBS volumes are network-attached block storage, living in **one AZ**, attachable to instances in the same AZ.

| Volume type | Kind | Performance | Use case |
|-------------|------|-------------|----------|
| **gp3** | General purpose SSD | 3,000 IOPS and 125 MiB/s baseline, configurable independently of size | Default for most workloads, boot volumes |
| **gp2** | General purpose SSD (older) | IOPS scale with size (3 IOPS/GiB) | Legacy, migrate to gp3 |
| **io2 Block Express** | Provisioned IOPS SSD | Up to 256,000 IOPS, 99.999% durability | Critical databases |
| **st1** | Throughput optimized HDD | High sequential throughput | Big data, log processing (cannot be a boot volume) |
| **sc1** | Cold HDD | Lowest cost | Infrequently accessed data |

**Snapshots** are point-in-time, incremental backups of a volume stored in S3 (managed by AWS). They can be copied across regions, used to create AMIs, and automated with **Amazon Data Lifecycle Manager** or **AWS Backup**. EBS encryption uses KMS and can be enabled by default per region.

Instance store is different: it is physically attached, very fast, but **ephemeral** (data is lost on stop or terminate).

## Public vs private IP

| | Private IPv4 | Public IPv4 | Elastic IP |
|---|---|---|---|
| Reachable from | Inside the VPC (and peered/VPN networks) | Internet | Internet |
| Assigned | From the subnet CIDR, always | Auto-assigned if the subnet/launch setting enables it | Allocated to my account, then associated |
| On stop/start | Kept | **Changes** | Kept |
| Cost | Free | Charged per hour (AWS bills all public IPv4 since Feb 2024) | Charged per hour, whether attached or not |

The public IP is not configured inside the OS: the Internet Gateway does 1:1 NAT between the public and private address. An Elastic IP is useful when something needs a fixed address, but a load balancer + DNS name is usually the better design.

## Instance lifecycle

```
           launch
             |
          pending ---------> running <---------+
                               |   |           |
                     stop      |   | reboot    | start
                               v   +-----------+
                            stopping ---> stopped
                               |
          terminate (from running or stopped)
                               v
                         shutting-down ---> terminated
```

| State | Billed for compute? | Notes |
|-------|---------------------|-------|
| `pending` | No | Instance is booting |
| `running` | **Yes** | Per-second billing (60 s minimum) for Linux; EBS billed separately |
| `stopping` | No (yes if stopping to **hibernate**) | |
| `stopped` | No | EBS volumes and Elastic IPs are **still billed** |
| `shutting-down` | No | |
| `terminated` | No | Root EBS deleted by default (`DeleteOnTermination=true`); entry visible for ~1 hour |

**Hibernate** saves the RAM contents to the encrypted root EBS volume, so on start the applications resume where they left off. It must be enabled at launch. **Reboot** keeps the instance on the same host and keeps its public IP; **stop/start** usually moves it to new hardware.

## Common use cases

- Web and application servers (often in an Auto Scaling group behind an ALB).
- Self-managed databases or software that needs OS-level control.
- CI/CD build runners (Spot instances are cheap for this).
- Bastion hosts / jump boxes (though SSM Session Manager replaces most of these).
- GPU workloads for ML training and inference.
- Lift-and-shift migration of on-premises VMs.

## Terraform example

```hcl
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "ankit-key"
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens = "required" # enforce IMDSv2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOF

  tags = { Name = "ankit-web" }
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}
```

## AWS CLI examples

```bash
# Launch
aws ec2 run-instances --image-id ami-xxxxxxxx --instance-type t3.micro \
  --key-name ankit-key --security-group-ids sg-0abc123 --subnet-id subnet-0abc123 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ankit-web}]'

# List instances with state and IPs
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' \
  --output table

aws ec2 stop-instances      --instance-ids i-0123456789abcdef0
aws ec2 start-instances     --instance-ids i-0123456789abcdef0
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
```

<!-- REAL-OUTPUT: describe-instances table / terraform apply output for the EC2 instance -->

## What I learned

- The instance type name encodes family, generation, attributes and size, which makes choosing one much less random.
- "Stopped" does not mean free: EBS and public IPv4 addresses keep costing money.
- Security groups are stateful and allow-only, which keeps rules short compared to traditional firewalls.
- Using roles + IMDSv2 + SSM is safer than keys and open SSH ports.
