---
name: cloudflare-registrar
description: Cloudflare Registrar via mcporter: domain availability, prices, registration.
---

# Cloudflare Registrar

Use for Cloudflare Registrar domain availability, pricing, listing, and registration.

## Defaults

- MCP: `cloudflare-openclaw`
- Account: `OPENCLAW_CLOUDFLARE_ACCOUNT_ID`
- Token: `OPENCLAW_CLOUDFLARE_API_TOKEN`
- Source env first: `source ~/.profile`

## Guardrails

- Always run `domain-check` immediately before registration.
- Registration is billable/non-refundable. Ask Peter for explicit confirmation before `POST /registrar/registrations`.
- Do not print tokens.

## Commands

Check availability/pricing:

```bash
source ~/.profile
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "POST",
    path: `/accounts/${accountId}/registrar/domain-check`,
    body: { domains: ["example.com"] }
  });
}'
```

Register after confirmation:

```bash
source ~/.profile
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "POST",
    path: `/accounts/${accountId}/registrar/registrations`,
    body: { domain_name: "example.com", auto_renew: false, privacy_mode: "redaction" }
  });
}'
```

List registrations:

```bash
source ~/.profile
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "GET",
    path: `/accounts/${accountId}/registrar/registrations`
  });
}'
```
