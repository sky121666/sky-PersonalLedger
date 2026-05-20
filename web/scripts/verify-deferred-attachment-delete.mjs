import { readFileSync } from 'node:fs'

function read(path) {
  return readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
}

function requireMatch(source, pattern, message) {
  if (!pattern.test(source)) {
    throw new Error(message)
  }
}

function requireNoMatch(source, pattern, message) {
  if (pattern.test(source)) {
    throw new Error(message)
  }
}

const fileUpload = read('src/components/FileUpload.vue')
const removeFileMatch = fileUpload.match(
  /async function removeFile\(path: string\) \{[\s\S]*?\n\}/,
)
if (!removeFileMatch) {
  throw new Error('FileUpload removeFile function not found')
}
requireNoMatch(
  removeFileMatch[0],
  /fileApi\.delete\(/,
  'FileUpload must not delete existing uploaded files immediately on remove',
)

for (const path of [
  'src/components/TransactionDialog.vue',
  'src/views/LendingView.vue',
  'src/views/ReminderView.vue',
]) {
  const source = read(path)
  requireMatch(
    source,
    /deleteRemovedAttachments/,
    `${path} must clean removed original attachments after save`,
  )
}

console.log('deferred attachment delete contract ok')
