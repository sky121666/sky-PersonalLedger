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

router.beforeEach((to, _from, next) => {
  const authStore = useAuthStore()
  
  if (to.meta.requiresAuth && !authStore.isLoggedIn) {
    next('/login')
  } else if (to.path === '/login' && authStore.isLoggedIn) {
    next('/')
  } else {
    next()
  }
})

export default router
