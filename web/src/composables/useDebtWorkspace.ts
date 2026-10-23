import { ref, computed, onBeforeUnmount } from 'vue'
import { debtApi, type DebtCapabilities, type DebtCommand, type DebtOperation, type DebtOperationDetails, type DebtPlan, type DebtOperationQuery } from '@/api/debt'
import { accountApi, type Account } from '@/api/account'
import { authApi } from '@/api/auth'
import { createDebtJournal, isDebtWriteRejection, type PendingDebtWrite } from '@/utils/debtWriteJournal'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { notifyLedgerMutation } from '@/composables/useLedgerMutation'
import { toast } from '@/composables/useToast'

export function useDebtWorkspace() {
  const capabilities = ref<DebtCapabilities | null>(null)
  const accounts = ref<Account[]>([])
  const plans = ref<DebtPlan[]>([])
  const operations = ref<DebtOperation[]>([])
  const hasMoreOperations = ref(false)
  const historyLoading = ref(false)
  const historyError = ref('')
  let historyScope: { accountId: string; query: DebtOperationQuery } = { accountId: '', query: {} }
  const loading = ref(false)
  const hasLoaded = ref(false)
  const loadError = ref('')
  const userId = ref(0)
  const pending = ref<PendingDebtWrite | null>(null)
  const journalError = ref('')
  const saving = ref(false)
  const writeError = ref('')
  const detail = ref<DebtOperationDetails | null>(null)
  const detailLoading = ref(false)
  const detailError = ref('')
  const requests = createRequestGeneration()
  const detailRequests = createRequestGeneration()
  let alive = true
  const supported = computed(() => capabilities.value?.contract_version === 1 &&
    capabilities.value.multiple_plans && capabilities.value.explicit_allocation && capabilities.value.reversal)
  const canWrite = computed(() => supported.value && hasLoaded.value && !loading.value && !loadError.value &&
    userId.value > 0 && !saving.value && !pending.value && !journalError.value)

  async function loadData(accountId = '', query: DebtOperationQuery = {}) {
    const generation = requests.begin()
    loading.value = true
    loadError.value = ''
    historyLoading.value = false
    historyError.value = ''
    try {
      let caps: DebtCapabilities
      try { caps = await debtApi.capabilities() }
      catch (error) {
        if ((error as { status?: number }).status !== 404) throw error
        if (requests.isLatest(generation) && alive) {
          capabilities.value = null
          hasLoaded.value = true
        }
        return
      }
      if (!requests.isLatest(generation) || !alive) return
      capabilities.value = caps
      if (!supported.value) { hasLoaded.value = true; return }
      const [accountData, planData, operationData, profile] = await Promise.all([
        accountApi.getList(true), debtApi.plans(), debtApi.operations(accountId, query), authApi.getProfile(),
      ])
      if (!requests.isLatest(generation) || !alive) return
      accounts.value = accountData.list
      plans.value = planData ?? []
      operations.value = operationData ?? []
      historyScope = { accountId, query: { ...query } }
      hasMoreOperations.value = caps.operation_history === true && operations.value.length === 100
      userId.value = profile.id
      journalError.value = ''
      try { pending.value = createDebtJournal(profile.id).read() }
      catch (error) { journalError.value = (error as Error).message }
      hasLoaded.value = true
    } catch (error) {
      if (requests.isLatest(generation) && alive) loadError.value = (error as Error).message || '分期数据加载失败'
    } finally {
      if (requests.isLatest(generation) && alive) loading.value = false
    }
  }

  async function loadMoreOperations() {
    if (!hasMoreOperations.value || loading.value || historyLoading.value) return
    const before = operations.value[operations.value.length - 1]?.id
    if (!before) return
    const generation = requests.begin()
    historyLoading.value = true
    historyError.value = ''
    try {
      const page = await debtApi.operations(historyScope.accountId, { ...historyScope.query, before })
      if (!requests.isLatest(generation) || !alive) return
      const seen = new Set(operations.value.map(operation => operation.id))
      operations.value = [...operations.value, ...page.filter(operation => !seen.has(operation.id))]
      hasMoreOperations.value = page.length === 100
    } catch (error) {
      if (requests.isLatest(generation) && alive) historyError.value = (error as Error).message || '更早凭证加载失败，请重试'
    } finally {
      if (requests.isLatest(generation) && alive) historyLoading.value = false
    }
  }

  async function openOperation(id: string) {
    const generation = detailRequests.begin()
    detail.value = null
    detailError.value = ''
    detailLoading.value = true
    try {
      const result = await debtApi.details(id)
      if (detailRequests.isLatest(generation) && alive) detail.value = result
    } catch (error) {
      if (detailRequests.isLatest(generation) && alive) detailError.value = (error as Error).message || '凭证加载失败'
    } finally {
      if (detailRequests.isLatest(generation) && alive) detailLoading.value = false
    }
  }

  function closeOperation() {
    detailRequests.begin()
    detail.value = null
    detailError.value = ''
    detailLoading.value = false
  }

  async function execute(command?: DebtCommand) {
    if (saving.value || !supported.value || !userId.value || journalError.value) return false
    if (command && !canWrite.value) return false
    saving.value = true
    writeError.value = ''
    const id = userId.value
    let attempted: PendingDebtWrite | null = null
    try {
      const journal = createDebtJournal(id)
      const record = command ? journal.stage(command) : journal.read()
      if (!record) throw Error('没有待确认操作')
      attempted = journal.attempt(record)
      if (alive) pending.value = attempted
      await debtApi.send(attempted, attempted.key)
      // Success remains a ledger mutation even if this view was closed while
      // waiting. The transport already rejects superseded auth sessions.
      notifyLedgerMutation()
      const cleared = journal.clear(attempted)
      if (alive && userId.value === id) {
        pending.value = journal.read()
        if (!cleared) throw Error('另一轮结果确认仍在进行，请继续确认上次操作')
        toast.success('操作已确认')
      }
      return cleared
    } catch (error) {
      // A refusal of a later confirmation cannot prove that the first
      // attempt did not commit. Only a definite first-attempt rejection clears it.
      if (attempted?.attempt === 1 && isDebtWriteRejection(error)) {
        try { createDebtJournal(id).clear(attempted) }
        catch (storageError) { if (alive) journalError.value = (storageError as Error).message }
      }
      if (alive && userId.value === id) {
        try { pending.value = createDebtJournal(id).read() }
        catch (storageError) { journalError.value = (storageError as Error).message }
        writeError.value = (error as Error).message || '操作结果尚未确认'
      }
      return false
    } finally {
      if (alive) saving.value = false
    }
  }

  onBeforeUnmount(() => {
    alive = false
    requests.begin()
    detailRequests.begin()
  })
  return { capabilities, accounts, plans, operations, hasMoreOperations, historyLoading, historyError, loading, hasLoaded, loadError, pending, journalError,
    saving, writeError, detail, detailLoading, detailError, supported, canWrite, userId,
    loadData, loadMoreOperations, openOperation, closeOperation, execute }
}
