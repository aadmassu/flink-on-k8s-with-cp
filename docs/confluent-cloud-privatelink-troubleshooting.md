# Confluent Cloud PrivateLink — Troubleshooting Guide

**Audience:** Infrastructure engineers using a Windows Desktop (EC2) inside AWS to access a Confluent Cloud Enterprise cluster over PrivateLink.

---

## Problem Statement

When accessing a Confluent Cloud Enterprise cluster configured with AWS PrivateLink, the Confluent Cloud Console shows **"Managing topics not available"** and the Message Viewer does not load topic data — even when browsing from a Windows jumpbox inside the VPC.

## How It Works

The Confluent Cloud Console is a **public web application** at `confluent.cloud`. When you open the Message Viewer, your browser makes REST API calls to the cluster's **private endpoint** (e.g., `lkc-XXXXX.us-east-2.aws.private.confluent.cloud:443`).

For the Message Viewer to work, your browser must be able to **resolve and reach** that private endpoint. This requires:

- The machine running the browser is **inside the VPC** where the PrivateLink VPC endpoint was created
- The VPC has **Route 53 private hosted zones** with the correct DNS records
- The **VPC endpoint** is in the `available` state
- **Security groups** allow traffic on ports 443 and 9092

---

## Troubleshooting Steps

### Step 1: Verify the Windows Desktop Is in the Correct VPC

The Windows desktop must be in the **same VPC** where the PrivateLink VPC endpoint was created.

**In the AWS Console:**

1. Go to **EC2 > Instances**
2. Select your Windows desktop instance
3. In the **Details** tab, note the **VPC ID** (e.g., `vpc-0abc123...`)
4. Go to **VPC > Endpoints**
5. Find the Confluent PrivateLink endpoint and verify its **VPC ID** matches

If the VPC IDs do not match, the Windows desktop cannot use the private hosted zones and will not resolve the private Kafka endpoints.

---

### Step 2: Verify the VPC Endpoint Is Available

**In the AWS Console:**

1. Go to **VPC > Endpoints**
2. Find the endpoint associated with Confluent (service name contains `vpce-svc-`)
3. Check the **Status** column

| Status | Meaning |
|---|---|
| `available` | Working — Confluent has accepted the endpoint |
| `pendingAcceptance` | Confluent has not accepted yet — check the Confluent Cloud access point status |
| `failed` | Something went wrong — recreate the endpoint |

Also note the **DNS names** listed on the endpoint detail page. You will need these for the DNS records (Step 3).

---

### Step 3: Verify DNS Resolution (Most Common Issue)

**On the Windows desktop, open Command Prompt or PowerShell:**

```
nslookup lkc-XXXXX.us-east-2.aws.private.confluent.cloud
```

**Expected result:** Returns one or more private IP addresses (e.g., `10.x.x.x`).

**If you see "Non-existent domain" or the query returns a public IP:**

The Route 53 private hosted zone is missing or misconfigured. Check the following:

#### 3a. Verify the Private Hosted Zone Exists

**In the AWS Console:**

1. Go to **Route 53 > Hosted zones**
2. Look for a zone named `us-east-2.aws.private.confluent.cloud` (adjust region as needed)
3. Verify the **Type** column shows **Private**
4. Click on the zone and verify under **Hosted zone details** that it is **Associated with your VPC**

If the zone does not exist, it must be created. If it exists but is not associated with the VPC, associate it.

#### 3b. Verify the CNAME Records

Inside the private hosted zone, you need **4 CNAME records**:

| Record Name | Record Type | Value (points to) |
|---|---|---|
| `*.us-east-2.aws.private.confluent.cloud` | CNAME | `vpce-XXXXX.vpce-svc-XXXXX.us-east-2.vpce.amazonaws.com` |
| `*.use2-az1.us-east-2.aws.private.confluent.cloud` | CNAME | `vpce-XXXXX-us-east-2a.vpce-svc-XXXXX.us-east-2.vpce.amazonaws.com` |
| `*.use2-az2.us-east-2.aws.private.confluent.cloud` | CNAME | `vpce-XXXXX-us-east-2b.vpce-svc-XXXXX.us-east-2.vpce.amazonaws.com` |
| `*.use2-az3.us-east-2.aws.private.confluent.cloud` | CNAME | `vpce-XXXXX-us-east-2c.vpce-svc-XXXXX.us-east-2.vpce.amazonaws.com` |

The first record (`*`) handles the bootstrap endpoint. The three zonal records (`*.use2-az1`, `*.use2-az2`, `*.use2-az3`) handle individual broker connections. Each zonal record must point to the **corresponding availability zone DNS name** from the VPC endpoint.

To find the correct values:
1. Go to **VPC > Endpoints** in the AWS Console
2. Click on your Confluent endpoint
3. Under the **DNS names** section, the first entry is the bootstrap DNS, followed by the zonal entries (they include `-us-east-2a`, `-us-east-2b`, `-us-east-2c` in the name)
4. Under the **Subnets** tab, you can see which availability zone ID (e.g., `use2-az1`) maps to which availability zone name (e.g., `us-east-2a`)

#### 3c. Check for Conflicting Public Hosted Zones

In **Route 53 > Hosted zones**, check if there is a **public** hosted zone with the same name (`us-east-2.aws.private.confluent.cloud`). A public zone with this name will return an authoritative NXDOMAIN that gets cached by the VPC DNS resolver for up to **24 hours**.

If a conflicting public zone exists, **delete it**. After deletion, you may need to **stop and start** (not reboot) the Windows desktop EC2 instance to clear the VPC resolver cache.

#### 3d. Flush DNS Cache on Windows

**Open Command Prompt as Administrator:**

```
ipconfig /flushdns
```

Then retry `nslookup`.

If it still fails after flushing, the VPC resolver itself may have a cached negative response. **Stop and start** the EC2 instance from the AWS Console (EC2 > Instances > select instance > Instance state > Stop instance, then Start instance). This forces a fresh connection to the VPC DNS resolver.

---

### Step 4: Verify VPC DNS Settings

**In the AWS Console:**

1. Go to **VPC > Your VPCs**
2. Select the VPC where the endpoint lives
3. Check that both settings are **Enabled**:
   - **DNS hostnames**: Enabled
   - **DNS resolution**: Enabled

If either is disabled:
1. Select the VPC
2. Click **Actions > Edit DNS hostnames** (or **Edit DNS resolution**)
3. Check the box and save

---

### Step 5: Verify Security Groups

The security group attached to the VPC endpoint must allow inbound traffic from the Windows desktop.

**In the AWS Console:**

1. Go to **VPC > Endpoints**
2. Click on the Confluent endpoint
3. Under **Security groups**, click the security group ID
4. Check the **Inbound rules** tab

You need these rules:

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 443 | TCP | VPC CIDR (e.g., `10.0.0.0/16`) | REST API (Console message viewer) |
| 9092 | TCP | VPC CIDR | Kafka bootstrap and broker connections |

If port 9092 is missing, click **Edit inbound rules** and add it.

---

### Step 6: Test Port Connectivity

**On the Windows desktop, open PowerShell:**

```powershell
# Test port 443 (REST API)
Test-NetConnection lkc-XXXXX.us-east-2.aws.private.confluent.cloud -Port 443

# Test port 9092 (Kafka)
Test-NetConnection lkc-XXXXX.us-east-2.aws.private.confluent.cloud -Port 9092
```

**Expected:** Both show `TcpTestSucceeded : True`.

If port 443 fails, the security group or network ACL is blocking it. If port 9092 fails, add the inbound rule (Step 5).

---

### Step 7: Test the REST API

**On the Windows desktop, open PowerShell:**

```powershell
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("API_KEY:API_SECRET"))
}
Invoke-RestMethod -Uri "https://lkc-XXXXX.us-east-2.aws.private.confluent.cloud:443/kafka/v3/clusters/lkc-XXXXX/topics" -Headers $headers
```

Replace `API_KEY`, `API_SECRET`, and `lkc-XXXXX` with your values.

**Expected:** Returns a JSON list of topics.

If this works in PowerShell but the Confluent Cloud Console message viewer still doesn't load, check:

- The browser is not using a corporate proxy that bypasses VPC DNS
- Clear the browser cache: **Ctrl+Shift+Delete > Clear cached images and files**
- Try a different browser (Edge, Chrome, Firefox)

---

### Step 8: Verify the Confluent Cloud Access Point

**In the Confluent Cloud Console:**

1. Go to **Environment > Network management**
2. Click the **For serverless products** tab
3. Click on your gateway (e.g., `aws-pl-gw`)
4. Under **Access points**, verify the status shows **Ready** (green checkmark)
5. Click the **Resources** tab and verify the Kafka cluster shows **Running**

If the access point shows **Provisioning**, wait 10-15 minutes. If it stays in Provisioning for longer than 30 minutes, verify the VPC endpoint ID you registered matches the actual endpoint in your AWS account.

---

## Common Issues and Fixes

| Symptom | Root Cause | Fix |
|---|---|---|
| `nslookup` returns "Non-existent domain" | Private hosted zone missing or not associated with VPC | Create the hosted zone with 4 CNAME records in Route 53 (Step 3) |
| `nslookup` fails despite correct zone | Conflicting public hosted zone returning cached NXDOMAIN | Delete the public zone, then stop/start the EC2 instance (Step 3c) |
| DNS resolves but `Test-NetConnection` fails on 9092 | Security group missing port 9092 | Add inbound rule for 9092/TCP from VPC CIDR (Step 5) |
| DNS resolves but SSL errors | Confluent gateway still provisioning | Wait for access point to show Ready (Step 8) |
| Console shows "Managing topics not available" | Browser is not inside the VPC | You must browse from the Windows desktop inside the VPC |
| PowerShell REST call works but browser doesn't | Browser using corporate proxy | Bypass proxy for `*.private.confluent.cloud` or clear browser cache |

---

## Architecture Reference

```
Your Laptop (corporate network / public internet)
    |
    +-- confluent.cloud (public UI) --- loads normally
    |
    +-- lkc-XXXXX.us-east-2.aws.private.confluent.cloud:443 --- FAILS
        (your laptop cannot resolve or route to the private endpoint)


Windows Desktop (inside AWS VPC)
    |
    +-- confluent.cloud (public UI) --- loads normally (via Internet Gateway)
    |
    +-- lkc-XXXXX.us-east-2.aws.private.confluent.cloud:443
            |
            +-- Route 53 private zone resolves to VPC endpoint IPs (10.x.x.x)
            |
            +-- VPC Endpoint --- AWS PrivateLink --- Confluent Cloud
```

**Key insight:** The Confluent Cloud UI loads from the public internet, but the data plane API calls (topic listing, message viewing, producing, consuming) go to the **private endpoint**. Both must be reachable from the same browser session. This is only possible from a machine **inside the VPC**.

---

## Checklist Summary

Use this checklist to quickly verify all prerequisites:

- [ ] Windows desktop is in the **same VPC** as the VPC endpoint
- [ ] VPC endpoint status is **available**
- [ ] VPC has **DNS hostnames** and **DNS resolution** enabled
- [ ] Route 53 private hosted zone exists for `us-east-2.aws.private.confluent.cloud`
- [ ] Private hosted zone is **associated with the VPC**
- [ ] Zone has **4 CNAME records** (1 bootstrap wildcard + 3 zonal wildcards)
- [ ] **No conflicting public hosted zone** with the same domain name
- [ ] Security group allows **port 443** and **port 9092** from VPC CIDR
- [ ] `nslookup` from Windows returns **private IPs** (10.x.x.x)
- [ ] `Test-NetConnection` succeeds on both **port 443** and **port 9092**
- [ ] Confluent Cloud access point shows **Ready**
- [ ] Browsing from the Windows desktop **inside the VPC** (not from your laptop)
