import type { Locator } from '@playwright/test'

export async function selectWidgetAccount(gallery: Locator, id: string) {
  await gallery.getByRole('button', { name: '组件关联账户', exact: true }).click()
  await gallery.getByRole('listbox', { name: '可选账户' }).locator(`button[value=${JSON.stringify(id)}]`).click()
}
