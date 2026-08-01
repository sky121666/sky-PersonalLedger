import type { Account, AccountListResponse } from '@/api/account'
import type { Category } from '@/api/category'
import type { FamilyMember } from '@/api/family'
import type { Tag } from '@/api/tag'

export type TransactionDialogOptionSource =
  | 'categories'
  | 'accounts'
  | 'familyMembers'
  | 'tags'

export interface TransactionDialogOptionLoaders {
  categories: () => Promise<Category[]>
  accounts: () => Promise<AccountListResponse>
  familyMembers: () => Promise<FamilyMember[]>
  tags: () => Promise<Tag[]>
}

export interface TransactionDialogOptions {
  categories: Category[]
  accounts: Account[]
  familyMembers: FamilyMember[]
  tags: Tag[]
  failures: Partial<Record<TransactionDialogOptionSource, unknown>>
}

export async function loadTransactionDialogOptions(
  loaders: TransactionDialogOptionLoaders,
): Promise<TransactionDialogOptions> {
  const [categoryResult, accountResult, familyResult, tagResult] =
    await Promise.allSettled([
      invoke(loaders.categories),
      invoke(loaders.accounts),
      invoke(loaders.familyMembers),
      invoke(loaders.tags),
    ] as const)

  const failures: TransactionDialogOptions['failures'] = {}
  recordFailure(failures, 'categories', categoryResult)
  recordFailure(failures, 'accounts', accountResult)
  recordFailure(failures, 'familyMembers', familyResult)
  recordFailure(failures, 'tags', tagResult)

  return {
    categories: fulfilledValue(categoryResult, []),
    accounts: fulfilledValue(accountResult, {
      list: [],
      total_assets: 0,
      total_liabilities: 0,
      net_assets: 0,
    }).list,
    familyMembers: fulfilledValue(familyResult, []),
    tags: fulfilledValue(tagResult, []),
    failures,
  }
}

function invoke<T>(loader: () => Promise<T>): Promise<T> {
  return Promise.resolve().then(loader)
}

function fulfilledValue<T>(result: PromiseSettledResult<T>, fallback: T): T {
  return result.status === 'fulfilled' ? result.value : fallback
}

function recordFailure<T>(
  failures: TransactionDialogOptions['failures'],
  source: TransactionDialogOptionSource,
  result: PromiseSettledResult<T>,
) {
  if (result.status === 'rejected') {
    failures[source] = result.reason
  }
}
