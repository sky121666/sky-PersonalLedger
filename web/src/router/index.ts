import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { requiresAuth: false }
    },
    {
      path: '/setup',
      name: 'setup',
      component: () => import('@/views/SetupView.vue'),
      meta: { requiresAuth: false }
    },
    {
      path: '/',
      component: () => import('@/views/LayoutView.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'home',
          component: () => import('@/views/HomeView.vue')
        },
        {
          path: 'transactions',
          name: 'transactions',
          component: () => import('@/views/TransactionsView.vue')
        },
        {
          path: 'statistics',
          name: 'statistics',
          component: () => import('@/views/StatisticsView.vue')
        },
        {
          path: 'settings',
          name: 'settings',
          component: () => import('@/views/SettingsView.vue')
        },
        {
          path: 'accounts',
          name: 'accounts',
          component: () => import('@/views/AccountsView.vue')
        },
        {
          path: 'categories',
          name: 'categories',
          component: () => import('@/views/CategoryView.vue')
        },
        {
          path: 'budgets',
          name: 'budgets',
          component: () => import('@/views/BudgetView.vue')
        },
        {
          path: 'reminders',
          name: 'reminders',
          component: () => import('@/views/ReminderView.vue')
        },
        {
          path: 'lendings',
          name: 'lendings',
          component: () => import('@/views/LendingView.vue')
        },
        {
          path: 'report',
          name: 'report',
          component: () => import('@/views/ReportView.vue')
        },
        {
          path: 'account-logs',
          name: 'account-logs',
          component: () => import('@/views/AccountLogView.vue')
        },
        {
          path: 'account-logs/:id',
          name: 'account-log-detail',
          component: () => import('@/views/AccountLogView.vue')
        }
      ]
    }
  ]
})

router.beforeEach(async (to) => {
  const authStore = useAuthStore()

  if (authStore.initialized === null) {
    await authStore.checkAuth()
  }

  if (authStore.initialized === false) {
    authStore.logout()
    return to.path === '/setup' ? true : '/setup'
  }

  if (to.path === '/setup') {
    return authStore.isLoggedIn ? '/' : '/login'
  }

  if (to.meta.requiresAuth && !authStore.isLoggedIn) {
    return '/login'
  }
  if (to.path === '/login' && authStore.isLoggedIn) {
    return '/'
  }

  return true
})

export default router
