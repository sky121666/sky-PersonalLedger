# AI Analysis

## Decision

Personal Ledger should add an optional AI analysis layer for weekly reports, monthly reports, family spending insights, budget suggestions, and anomaly explanations. The integration should use an OpenAI-compatible chat completions API so DeepSeek, OpenAI, One API, SiliconFlow, local gateways, and other compatible providers can be supported through the same adapter.

AI analysis must be disabled by default. Financial data is sensitive, so the backend should aggregate and minimize data before sending it to an external provider. Raw transaction remarks and full transaction lists should not be sent by default.

## Provider Model

### New Table: `ai_providers`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string UUID | Primary key |
| `user_id` | uint | Existing owner user |
| `name` | string | Display name, e.g. DeepSeek |
| `provider_type` | string | First value: `openai_compatible` |
| `base_url` | string | Base URL, e.g. `https://api.deepseek.com` |
| `api_key_ciphertext` | string | AES-GCM protected value when `LEDGER_JWT_SECRET` is configured; never return raw key |
| `model` | string | e.g. `deepseek-chat` |
| `enabled` | bool | Main switch |
| `created_at` | time | GORM timestamp |
| `updated_at` | time | GORM timestamp |

The API key must not be logged, exported in diagnostics, returned in API responses, or included in backup files unless an explicit encrypted backup strategy is added later. Runtime storage protects new keys with AES-GCM using a key derived from `LEDGER_JWT_SECRET`; legacy plain values remain readable for backward compatibility and should be rotated by saving the provider again after upgrading.

Provider setup exposes non-secret OpenAI-compatible presets for DeepSeek, OpenAI, SiliconFlow, and custom gateways. Presets only fill display name, base URL, provider type, and model choices. Users must still provide their own API key, and no preset performs an external request until the user saves and tests a provider.

## Report Model

### New Table: `ai_reports`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string UUID | Primary key |
| `user_id` | uint | Owner |
| `report_type` | string | `weekly`, `monthly`, `family`, `budget`, `anomaly` |
| `period_start` | date | Report period start |
| `period_end` | date | Report period end |
| `status` | string | `pending`, `running`, `completed`, `failed` |
| `snapshot_json` | text | Aggregated local facts sent to the model |
| `content_json` | text | Structured AI output |
| `provider_name` | string | Provider used |
| `model` | string | Model used |
| `prompt_version` | string | Template version |
| `error_message` | string | Sanitized error |
| `created_at` | time | GORM timestamp |
| `updated_at` | time | GORM timestamp |

## OpenAI-Compatible Request

The adapter should target chat completions:

```json
{
  "model": "deepseek-chat",
  "messages": [
    {
      "role": "system",
      "content": "You are a financial analysis assistant for a private household ledger. Use only the provided facts."
    },
    {
      "role": "user",
      "content": "{aggregated_report_snapshot_json}"
    }
  ],
  "temperature": 0.2
}
```

The adapter must support providers whose base URL either includes or omits `/v1`. Normalize to `POST {base_url}/v1/chat/completions` unless the saved base URL already ends with `/v1`.

## Snapshot Shape

Weekly and monthly reports should send aggregated facts:

```json
{
  "period": {
    "start": "2026-05-18",
    "end": "2026-05-24",
    "timezone": "Asia/Shanghai"
  },
  "currency": "CNY",
  "income_total": 12000,
  "expense_total": 4380.5,
  "net_cashflow": 7619.5,
  "budget": {
    "monthly_budget": 8000,
    "spent": 4380.5,
    "remaining": 3619.5,
    "used_percent": 54,
    "over_budget_categories": [],
    "member_budgets": []
  },
  "top_expense_categories": [
    {
      "name": "餐饮",
      "amount": 1280,
      "change_percent": 18
    }
  ],
  "family_members": [
    {
      "display_name": "成员A",
      "expense_total": 2100,
      "top_category": "餐饮"
    }
  ],
  "account_changes": [
    {
      "account_name": "现金",
      "balance_delta": -300
    }
  ]
}
```

Names should be anonymized when the user enables data masking. Remarks should be excluded by default.

## AI Output Contract

Reports should be stored as structured JSON rather than only Markdown:

```json
{
  "title": "本周财务总结",
  "summary": "本周支出保持可控，餐饮支出较上周上升。",
  "highlights": [
    "净现金流为正",
    "餐饮支出上升 18%"
  ],
  "risks": [
    {
      "level": "medium",
      "title": "餐饮支出增加",
      "detail": "本周餐饮支出高于近期均值。"
    }
  ],
  "suggestions": [
    "下周可将餐饮预算控制在 1000 元以内。"
  ]
}
```

The UI can render this contract as cards, timeline blocks, and short paragraphs.

## API Surface

| Endpoint | Method | Behavior |
| --- | --- | --- |
| `/api/v1/ai/providers/presets` | GET | List non-secret provider presets |
| `/api/v1/ai/providers` | GET | List providers without API keys |
| `/api/v1/ai/providers` | POST | Create provider |
| `/api/v1/ai/providers/:id` | PUT | Update provider |
| `/api/v1/ai/providers/:id` | DELETE | Delete provider |
| `/api/v1/ai/providers/:id/test` | POST | Test connection with non-financial prompt |
| `/api/v1/ai/reports` | GET | List generated reports |
| `/api/v1/ai/reports/generate` | POST | Generate report for type and period |
| `/api/v1/ai/reports/:id` | GET | Read report |
| `/api/v1/ai/reports/:id` | DELETE | Delete report |

## Privacy Rules

- Default off.
- Explicit enablement required.
- Show which aggregated fields will be sent.
- Do not send raw transaction lists by default.
- Do not send file attachments.
- Do not send API tokens, passwords, webhook URLs, or backup contents.
- Provide a masking option for member names and account names.
- Cache reports to avoid repeated external calls.
- Allow deleting reports.
- Protect stored provider API keys at rest.
- Keep AI providers and raw provider keys out of normal ledger backup exports.

## Validation

- Unit tests for base URL normalization.
- Unit tests for provider response parsing.
- Handler tests proving API keys are not returned.
- Report generation test using a fake OpenAI-compatible server.
- Snapshot tests proving raw remarks are excluded by default.
- UI tests for disabled state, connection test, and generated report rendering.
