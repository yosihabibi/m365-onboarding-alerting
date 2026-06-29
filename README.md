# M365 Onboarding & Alerting Automation

Automate Microsoft 365 employee **onboarding** and **certificate/secret expiry alerting** with
**n8n**, the **Microsoft Graph API**, and a modular **PowerShell** module — built with an MSP mindset
and reusable across tenants.

## What it does

Two n8n workflows + one PowerShell module:

1. **Onboarding workflow** — one form submit **creates a user → assigns a license → posts a Teams
   notification** via Microsoft Graph (OAuth 2.0 client credentials). Replaces ~6 manual steps.
2. **Certificate / secret expiry alerting** — a PowerShell module checks Entra **app registrations**
   for expiring **certificates and client secrets** and `POST`s the findings to an **n8n webhook**,
   which raises a **Teams alert** (e.g. 14 days before expiry).

## Architecture

```
[PowerShell: M365CertGuard]  --finds expiring secret/cert-->  POST webhook
                                                                  |
                                                                  v
                                              [n8n: cert-alerting workflow]  -->  Teams alert

[n8n: onboarding workflow]  --OAuth2 (client credentials)-->  Microsoft Graph
   Form  ->  create user  ->  assign license  ->  Teams notification
```

Result: exactly **2 workflows + 1 module**, loosely coupled via a webhook (DRY, reusable per tenant).

## Components

| Path | What |
|---|---|
| `powershell/M365CertGuard/` | PowerShell module: `Connect-CertGuard`, `Get-AppCredentialExpiry`, `Send-CertExpiryWebhook` (+ a private DRY helper) |
| `powershell/Invoke-CertCheck.ps1` | Runner for the module (lists expiring credentials, optional webhook alert) |
| `powershell/Test-GraphToken.ps1` | Minimal raw-REST OAuth2 token test (verifies app registration + admin consent) |
| `n8n/onboarding-workflow.json` | Workflow 1 — onboarding (form → user → license → Teams) |
| `n8n/cert-alerting-workflow.json` | Workflow 2 — webhook receiver → Teams alert |

## Prerequisites

- A Microsoft 365 / Entra tenant
- An **Entra app registration** (client credentials) with **application** Graph permissions + admin consent:
  - `User.ReadWrite.All` — create users, assign licenses
  - `Organization.Read.All` — read available licenses (`subscribedSkus`)
  - `Application.Read.All` — read app certificates & secrets (the cert checker)
- **PowerShell 5.1+** with `Microsoft.Graph.Authentication` and `Microsoft.Graph.Applications`
- **n8n** (e.g. via Docker)
- A **Teams "Workflows" webhook** (Power Automate) for posting alerts/notifications

## Setup

1. Set the (non-secret) app identifiers as environment variables:
   ```powershell
   $env:GRAPH_TENANT_ID = "<your-tenant-id>"
   $env:GRAPH_CLIENT_ID = "<your-client-id>"
   ```
   The **client secret is never stored** — it is requested at runtime as a `SecureString`.
2. Install the Graph modules:
   ```powershell
   Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications -Scope CurrentUser
   ```
3. In n8n, **import** both workflows (`Import from File`). Then:
   - Create an **OAuth2 API** credential — grant type **Client Credentials**,
     token URL `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`,
     scope `https://graph.microsoft.com/.default`.
   - In each node that posts to Teams, paste **your own** Teams Workflows webhook URL
     (placeholder in the export: `<PASTE-YOUR-TEAMS-WORKFLOW-WEBHOOK-URL>`).

## Usage

**Certificate / secret check** (and optionally send the alert to n8n):
```powershell
cd powershell
.\Invoke-CertCheck.ps1 -WarningDays 14
.\Invoke-CertCheck.ps1 -WarningDays 14 -WebhookUrl "https://<n8n-host>/webhook/cert-alert"
```

**Onboarding**: open the n8n form (Form Trigger), enter first/last name → the user is created,
licensed, and a Teams card is posted — in one run.

## Security notes

- **No secrets in this repository.** The client secret is requested at runtime (`SecureString`);
  the Teams webhook URL is a placeholder and must be supplied per tenant.
- **Least privilege**: read-only Graph scopes wherever possible (the cert checker needs only
  `Application.Read.All`).
- App identifiers are read from environment variables, so the toolkit is **reusable across tenants**.

## Tech stack

Microsoft Graph API · Microsoft Entra ID · OAuth 2.0 (client credentials) · PowerShell (Graph SDK) ·
n8n · Microsoft Teams (Adaptive Cards) · Docker

## License

[MIT](LICENSE) © 2026 Yosef AL Fadili
