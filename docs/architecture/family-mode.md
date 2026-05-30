# Family Mode

## Decision

Personal Ledger should support a lightweight family mode for a trusted personal or household deployment. This is not a multi-tenant SaaS model and should not introduce public registration, organization billing, or complex role-based access control.

The first family-mode release should add family members as an accounting dimension. A member represents who a transaction belongs to, who paid, or who owns an account. Members do not need independent login accounts in the first version.

## Product Scope

| Area | Supported in first release | Deferred |
| --- | --- | --- |
| Member profiles | Name, avatar or icon, color, relationship, enabled state | Independent member login |
| Transaction ownership | Spending member and optional payer member | Split bills across many members |
| Account ownership | Optional owner member for accounts | Per-member account permissions |
| Budgets | Existing total/category budgets plus optional member budget | Complex approval workflow |
| Statistics | Member spending ranking and member/category breakdown | Predictive member profiling |
| Audit | Source device and actor label where available | Full enterprise audit trail |
| Permissions | Single administrator password and API tokens | RBAC, invitations, tenant isolation |

## Data Model

### New Table: `family_members`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string UUID | Primary key |
| `user_id` | uint | Existing owner user; keeps current single-owner deployment model |
| `name` | string | Required display name |
| `relationship` | string | Optional: self, spouse, child, parent, other |
| `avatar` | string | Optional upload path or icon name |
| `color` | string | Member accent color |
| `sort_order` | int | Stable ordering |
| `is_default` | bool | Default member for new records |
| `is_enabled` | bool | Disabled members remain in historical data |
| `created_at` | time | GORM timestamp |
| `updated_at` | time | GORM timestamp |
| `deleted_at` | soft delete | Preserve historical references |

### Existing Table Additions

| Table | New field | Purpose |
| --- | --- | --- |
| `transactions` | `member_id *string` | Who the spending/income belongs to |
| `transactions` | `paid_by_member_id *string` | Who actually paid or received |
| `accounts` | `owner_member_id *string` | Optional member-owned account |
| `budgets` | `member_id *string` | Optional member-specific budget |
| `account_logs` | `member_id *string` | Preserve member context for balance events |

Do not remove `user_id` in this phase. It remains the deployment owner and authorization boundary. Family mode is a product dimension inside the owner account, not a new tenant model.

## API Surface

| Endpoint | Method | Behavior |
| --- | --- | --- |
| `/api/v1/family/members` | GET | List enabled and disabled family members |
| `/api/v1/family/members` | POST | Create member profile |
| `/api/v1/family/members/:id` | PUT | Update member profile |
| `/api/v1/family/members/:id` | DELETE | Soft-delete or disable member when referenced |
| `/api/v1/family/summary` | GET | Family month summary and member ranking |
| `/api/v1/family/statistics` | GET | Monthly member ranking with per-member category breakdown |
| `/api/v1/budgets/total` | POST | Set owner-level or member-level total budget with optional `member_id` |
| `/api/v1/budgets/category` | POST | Set owner-level or member-level category budget with optional `member_id` |

Transaction create/update requests should accept `member_id` and `paid_by_member_id`. If `member_id` is omitted, the backend should use the default member when one exists and otherwise keep it empty for backward compatibility.

Budget create/update requests can include `member_id`. When omitted, budgets keep the existing owner-level total/category behavior. When present, the backend validates that the member belongs to the current owner account and returns member-scoped budget progress in `member_budgets`.

## Client Experience

### Web

Web can keep the current structure. Add family controls in focused areas:

- Settings: member management.
- Transaction dialog: member and payer selectors.
- Home: family summary strip.
- Statistics: member dimension filter.

### Flutter Mobile

Mobile should make family mode more visible:

- Profile tab: Family entry.
- Home dashboard: member spending cards and category breakdown.
- Quick transaction: member selector near amount/category.
- Statistics: segmented control for Overall / Members / Categories.

## Migration Strategy

1. Create `family_members`.
2. Add nullable member fields to existing tables.
3. Create a default member named from the current user nickname when practical.
4. Leave existing rows with null member fields unless the user chooses to backfill.
5. Add a later guided backfill screen if users want to assign historical records.

The first migration must be non-destructive and reversible at the data level by ignoring nullable member columns.

## Validation

Minimum verification for the first release:

- Backend tests for member CRUD and ownership checks.
- Transaction create/update tests with `member_id` and `paid_by_member_id`.
- Budget list tests for member-specific total/category budgets and ownership checks.
- Backup/restore tests include family members and member fields.
- Flutter widget tests for member selector.
- Real backend E2E creates a member, records a transaction, and sees member summary.

## Non-Goals

- Public user registration.
- Family invitation links.
- Independent family member passwords.
- Tenant administration.
- Per-field permissions.
- Offline multi-user conflict resolution.
