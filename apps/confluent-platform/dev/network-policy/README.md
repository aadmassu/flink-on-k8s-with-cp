# NetworkPolicy — Dev Environment Only

## Overview

NetworkPolicy resources are deployed **only in the dev environment**. The AZDO service account has the required RBAC permissions (`create/get/list/patch/delete` on `networkpolicies.networking.k8s.io`) in dev.

## Upper Environments (qa, uat-p, uat-s, prd, dr)

For NetworkPolicy creation in upper environments, the application team must:

1. **Submit a SNOW (ServiceNow) request** to the Infrastructure/Platform team
2. **Specify the required NetworkPolicy** (port, protocol, selectors, etc.)
3. **Wait for platform approval and implementation**

The AZDO pipeline will automatically skip NetworkPolicy application in non-dev environments and display a message:
```
NetworkPolicy: skipped for <environment> (requires SNOW request to infrastructure team).
```

## Why This Restriction?

- **Security boundary:** Network policies are low-level infrastructure controls
- **Audit trail:** Changes in upper environments must go through formal change management (SNOW)
- **Blast radius:** Misconfigured policies can block cluster-to-cluster communication

## Contact

For NetworkPolicy requests in upper environments, contact the **Infrastructure/Platform team** via SNOW.
