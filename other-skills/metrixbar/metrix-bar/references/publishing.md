# Registry Publishing Reference — Metrix.Bar

This reference covers packaging, validating, and distributing `.bar` dashboards via static registries or direct install links.

## Registry Format (`index.json`)

A registry is a static JSON file served over HTTPS (or HTTP on private local networks) that lists available dashboards:

```json
{
  "$schema": "https://metrix.bar/dashboards/schema.json",
  "schema_version": 1,
  "id": "my-team",
  "name": "My Team",
  "dashboards": [
    {
      "id": "traffic-monitor",
      "name": "Traffic Monitor",
      "file": "traffic-monitor.bar",
      "protocol_version": "0",
      "version": "1.0.0",
      "category": "analytics",
      "description": "Live traffic and request latency dashboard.",
      "icon": "activity",
      "license": "MIT",
      "homepage": "https://example.com/traffic",
      "docs": "Requires a read-only monitoring API key.",
      "sha256": "<SHA256_OF_RAW_BAR_BYTES>"
    }
  ]
}
```

Replace `<SHA256_OF_RAW_BAR_BYTES>` with the actual digest of the published file, or use `build.js` to calculate it automatically.

### Schema Rules

- `$schema`: Optional schema URI hint (`https://metrix.bar/dashboards/schema.json`). Tooling hint only; client implementations do not fetch it and rely solely on `schema_version: 1`.
- `schema_version`: Integer `1` (required).
- `id`: Registry slug matching `^[a-z0-9]+(?:-[a-z0-9]+)*$` without `--` (required).
- `name`: Non-empty display name string (required).
- `dashboards[].id`: Dashboard slug matching `^[a-z0-9]+(?:-[a-z0-9]+)*$` without `--`, unique within the registry (required).
- `dashboards[].file`: Relative path to the `.bar` file on the same origin (required).
- `dashboards[].protocol_version`: String `"0"` (required).
- `dashboards[].version`: Strict SemVer 2.0.0 string without `v` prefix (e.g. `"1.0.0"`) (required).
- `dashboards[].sha256`: Lowercase 64-character hexadecimal SHA-256 digest of the exact raw `.bar` bytes as published (required).
- `dashboards[].docs`: Optional plain text instructions extracted from `<docs>`, preserving internal newlines. No Markdown rendering; cannot be `null`.
- `dashboards[].category`: Optional category slug (e.g. `ai`, `analytics`, `development`, `finance`, `utilities`, `weather`). Defaults to `other`.
- `dashboards[].description`, `icon`, `license`: Optional string metadata.
- `dashboards[].homepage`: Optional absolute HTTPS URL string without credentials.

## Building Registries with `build.js`

Download and run the standalone builder from the official website:

```bash
curl -fsS https://metrix.bar/dashboards/build.js -o build.js
node build.js --input ./dashboards --output ./dist/dashboards --id my-team --name "My Team"
```

The builder requires Node 22+ and needs no package installation. It validates metadata, preserves raw file bytes, and computes SHA-256. Run `POST /v0/validate` and `POST /v0/check` before publishing to check source and runtime behavior as well. Publish the generated files together at a static HTTPS URL.

## Deep Links for Sharing

Metrix.Bar supports `metrixbar://` custom URI scheme links for user installation:

- **Add registry source**:
  ```text
  metrixbar://registry/add?url=https%3A%2F%2Fexample.com%2Fdashboards%2Findex.json
  ```
- **Install from registry**:
  ```text
  metrixbar://install/traffic-monitor?registry_url=https%3A%2F%2Fexample.com%2Fdashboards%2Findex.json
  ```
- **Install from configured registry**:
  ```text
  metrixbar://install/traffic-monitor?registry=my-team
  ```
- **Direct `.bar` file import**:
  ```text
  metrixbar://install?url=https%3A%2F%2Fexample.com%2Fdashboards%2Ftraffic-monitor.bar&sha256=<SHA256_OF_RAW_BAR_BYTES>
  ```
  *(Note: direct imports do not establish registry provenance and do not receive automatic update checks).*
