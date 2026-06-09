# Build Notes

The [README](../README.md) covers what the lab is. This covers how it came together and why I made the calls I did.

## Build order

I built it bottom-up so each layer had something to stand on.

Active Directory went in first. A Windows Server 2022 VM (UTM on Apple Silicon) promoted to a domain controller for `lab.local`, then the OU tree, security groups, and a few users modelled on a small financial-services org: portfolio managers, compliance, IT, a service account. That's the identity everything else points at.

Later I extended that identity to the cloud with Microsoft Entra ID. An Entra Cloud Sync agent on DC01 pushes the `LAB` OU tree (users, groups, service accounts) up to a tenant, so the same objects exist in both places, with AD as the source of truth. It came after AWS, but it belongs to Layer 1: it's still about identity, just no longer confined to the domain controller.

AWS came next, and I did it by hand before doing it in code. Stood up the S3 bucket, an EC2 instance, a security group, and an IAM role through the console, because clicking through it once is how you actually learn what the resources are. Then I brought them under Terraform by importing the live resources rather than rebuilding them, so the code matches what's really running. The import history is in [infra/terraform/README.md](../infra/terraform/README.md).

Automation and monitoring went in last: the PowerShell for AD user lifecycle and log shipping, then a Flask dashboard on the EC2 box so I can see the lab's state in a browser instead of digging through the AWS console.

## Decisions

**Imported existing infra into Terraform instead of rebuilding it.** The resources already existed and worked. Tearing them down to recreate them from scratch would have proved nothing. Terraform 1.5+ `import` blocks let me bring the bucket, instance, security group, and IAM role under code in place. The point isn't that I can write a `.tf` file. It's taking infrastructure that already exists and version-controlling it without downtime.

**IAM role on the instance, not stored keys.** The EC2 box reads S3 and queries EC2 through an attached role (`homelab-ec2-role`), so there are no access keys sitting on the server. It's the cheapest good habit in AWS.

**`louis-admin` is deliberately not in Terraform.** My admin identity stays out of the code so a bad `terraform destroy` can't lock me out of my own account.

**Used Cloud Sync instead of the full Entra Connect engine.** Both get the on-prem users into Entra. Cloud Sync is the lighter of the two: a small provisioning agent on DC01 with its configuration managed from the portal, instead of the full Connect sync engine and its local database. On a single domain controller running in a VM on Apple Silicon, lighter wins, and the free tier covers it. Connect would make sense at a scale this lab doesn't have.

**Renamed the tenant to a clean `.onmicrosoft.com`.** A free Azure account signed up with a personal address lands you with an ugly auto-generated tenant name (mine was my email mashed together) and an external/guest admin that can't manage domains. I created a native cloud admin, then added `distefanodev.onmicrosoft.com` through the M365 admin center's "Add onmicrosoft domain" flow and made it the default. `lab.local` itself isn't routable, so there's no real custom domain to verify. A domain I actually own would be the next step if this were ever more than a lab.

**Basic Auth on the dashboard, password from an env var.** Not SSO, but right-sized for one operator, and it keeps the credential out of the repo (`DASHBOARD_PASS` at runtime).

**Default tags on everything Terraform manages.** The provider stamps `Project=homelab`, `ManagedBy=terraform`, `Owner=louis` on every resource, so in the console I can tell code-managed infra from anything I clicked together.

## Things that bit me on the Entra sync

Two of these cost me real time, so they're worth writing down.

**The provisioning agent threw a `NullReferenceException` opening its signaling WebSocket.** The cloud config was correct, the agent registered fine and showed "active," but every sync cycle quarantined with `HybridIdentityServiceAgentTimeout` and the provisioning logs stayed empty. The Windows event log was useless. The real story was in the agent's own trace under `C:\ProgramData\Microsoft\Azure AD Connect Provisioning Agent\Trace`, which showed the agent reaching the regional Service Bus listeners but the TLS/WebSocket handshake nulling out. That pointed at certificate-chain validation, not raw connectivity: a domain controller is its own DNS server, and mine had no upstream forwarder, plus the CRL/OCSP checks (port 80) the TLS handshake needs weren't getting through. Adding a DNS forwarder on the DC and sorting the TLS/cert path is what got the WebSocket to establish and the first cycle to run. So when a healthy-looking agent never completes a cycle, go straight to its trace log; the cloud-side status won't tell you it's a cert/DNS problem.

**Synced users landed under the wrong domain until I gave them a routable UPN.** My AD users had `@lab.local` UPNs, which isn't a routable domain, so Cloud Sync fell back to the tenant's *initial* `.onmicrosoft.com` name rather than the `distefanodev` default I'd set. The fix is the right one for real hybrid anyway: add a routable UPN suffix in AD (`distefanodev.onmicrosoft.com`) and switch the users to it, so they sync up as `firstname.lastname@distefanodev.onmicrosoft.com`. Syncing `@lab.local` was never going to look right.

## Lab-grade, not prod-grade

It's a homelab, so a few things are intentionally looser than production: SSH open to the world, an unencrypted volume, local Terraform state. The [Terraform README](../infra/terraform/README.md#lab-grade-not-prod-grade) has the specifics. Taking this toward something real would start with locking down SSH and moving state to a remote backend; the rest follows from there.

The Azure side started on a free account (a $200 credit good for 30 days), and I've since moved it to pay-as-you-go so the tenant survives past that window for the long term. One upside of going PAYG: the Cost Management API starts working (the free-trial offer rejects it outright), so the private ops dashboard now pulls live Azure month-to-date spend instead of just counting down the credit. It still tracks the credit balance and its expiry, since that's what burns down before real charges begin, the same way it watches the Windows Server evaluation clock.
