<script setup lang="ts">
import AppDialog from '@/components/ui/AppDialog.vue'
import { ref, computed, onBeforeUnmount, watch } from 'vue'
import { Upload, X, FileText, Image, File, Download, Eye } from '@lucide/vue'
import { fileApi } from '@/api/file'
import { toast } from '@/composables/useToast'

const props = defineProps<{
  category: 'transactions' | 'lendings' | 'reminders'
  refId: string
  modelValue?: string // JSON array of file paths
  maxFiles?: number
  accept?: string
  disabled?: boolean
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
  'uploading-change': [value: boolean]
}>()

const uploading = ref(false)
const dragOver = ref(false)
const previewUrl = ref<string | null>(null)
const previewTrigger = ref<HTMLElement | null>(null)
const previewUrls = ref<Record<string, string>>({})
const objectUrls = new Map<string, string>()
const failedUploads = ref<File[]>([])
let active = true
// Keep emitted successes locally until the parent applies its v-model update.
const localModelValue = ref(props.modelValue)
watch(() => props.modelValue, value => { localModelValue.value = value })

const maxFilesLimit = computed(() => props.maxFiles ?? 5)
const acceptTypes = computed(() => props.accept || 'image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt')

const files = computed<string[]>(() => {
  if (!localModelValue.value) return []
  try {
    const parsed = JSON.parse(localModelValue.value)
    return Array.isArray(parsed) ? parsed.filter(path => typeof path === 'string') : []
  } catch {
    return []
  }
})

const canUpload = computed(() => {
  return !props.disabled && files.value.length < maxFilesLimit.value
})

function getFileIcon(path: string) {
  const ext = path.split('.').pop()?.toLowerCase()
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(ext || '')) {
    return Image
  }
  if (['pdf', 'doc', 'docx'].includes(ext || '')) {
    return FileText
  }
  return File
}

function getFileName(path: string) {
  return path.split('/').pop() || path
}

function isImage(path: string) {
  const ext = path.split('.').pop()?.toLowerCase()
  return ['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(ext || '')
}

async function getObjectUrl(path: string) {
  const cached = objectUrls.get(path)
  if (cached) return cached

  const objectUrl = await fileApi.previewObjectUrl(path)
  objectUrls.set(path, objectUrl)
  previewUrls.value = {
    ...previewUrls.value,
    [path]: objectUrl
  }
  return objectUrl
}

function revokeObjectUrl(path: string) {
  const objectUrl = objectUrls.get(path)
  if (!objectUrl) return

  URL.revokeObjectURL(objectUrl)
  objectUrls.delete(path)
  const next = { ...previewUrls.value }
  delete next[path]
  previewUrls.value = next
}

async function syncPreviewUrls() {
  const activeImages = new Set(files.value.filter(isImage))

  for (const path of objectUrls.keys()) {
    if (!activeImages.has(path)) {
      revokeObjectUrl(path)
    }
  }

  await Promise.all(
    [...activeImages]
      .filter(path => !objectUrls.has(path))
      .map(async path => {
        try {
          await getObjectUrl(path)
        } catch (error) {
          console.error('Preview load failed:', error)
        }
      })
  )
}

async function handleFileSelect(event: Event) {
  const input = event.target as HTMLInputElement
  if (input.files && input.files.length > 0) {
    await uploadFiles(Array.from(input.files))
  }
  input.value = '' // Reset input
}

function handleDragOver(event: DragEvent) {
  event.preventDefault()
  dragOver.value = true
}

function handleDragLeave() {
  dragOver.value = false
}

async function handleDrop(event: DragEvent) {
  event.preventDefault()
  dragOver.value = false
  
  if (event.dataTransfer?.files) {
    await uploadFiles(Array.from(event.dataTransfer.files))
  }
}

function sameFile(left: File, right: File) {
  return left.name === right.name && left.size === right.size &&
    left.type === right.type && left.lastModified === right.lastModified
}

async function uploadFiles(fileList: File[]) {
  if (uploading.value || !canUpload.value || fileList.length === 0) return
  
  const remainingSlots = maxFilesLimit.value - files.value.length
  const filesToUpload = fileList.slice(0, remainingSlots)
  if (fileList.length > remainingSlots) {
    toast.warning(`最多 ${maxFilesLimit.value} 个文件，本次仅上传前 ${remainingSlots} 个`)
  }
  
  uploading.value = true
  emit('uploading-change', true)
  
  try {
    for (const file of filesToUpload) {
      if (props.disabled || files.value.length >= maxFilesLimit.value) break
      const formData = new FormData()
      formData.append('file', file)
      formData.append('category', props.category)
      formData.append('ref_id', props.refId)

      try {
        const result = await fileApi.upload(formData)
        if (!active) break
        if (!result.path) throw new Error('上传响应缺少附件路径')
        updateFiles([...files.value, result.path])
        failedUploads.value = failedUploads.value.filter(failed => !sameFile(failed, file))
      } catch (error) {
        if (!active) break
        console.error('Upload failed:', error)
        if (!failedUploads.value.some(failed => sameFile(failed, file))) failedUploads.value.push(file)
        toast.error(`${file.name} 上传失败，可单独重试`)
      }
    }
  } finally {
    uploading.value = false
    if (active) emit('uploading-change', false)
  }
}

function updateFiles(paths: string[]) {
  localModelValue.value = JSON.stringify(paths)
  emit('update:modelValue', localModelValue.value)
}

async function removeFile(path: string) {
  const updatedFiles = files.value.filter(f => f !== path)
  updateFiles(updatedFiles)
}

async function openPreview(path: string, event?: Event) {
  if (typeof document !== 'undefined') {
    previewTrigger.value = event?.currentTarget instanceof HTMLElement ? event.currentTarget : document.activeElement as HTMLElement | null
  }
  try {
    if (isImage(path)) {
      previewUrl.value = await getObjectUrl(path)
    } else {
      await fileApi.download(path)
    }
  } catch (error) {
    console.error('Preview failed:', error)
    toast.error('预览失败')
  }
}

function closePreview() {
  previewUrl.value = null
}

async function downloadFile(path: string) {
  try {
    await fileApi.download(path)
  } catch (error) {
    console.error('Download failed:', error)
    toast.error('下载失败')
  }
}

watch(files, () => {
  void syncPreviewUrls()
}, { immediate: true })

onBeforeUnmount(() => {
  active = false
  emit('uploading-change', false)
  for (const objectUrl of objectUrls.values()) {
    URL.revokeObjectURL(objectUrl)
  }
  objectUrls.clear()
})
</script>

<template>
  <div class="space-y-3">
    <!-- File List -->
    <div v-if="files.length > 0" class="space-y-2">
      <div
        v-for="path in files"
        :key="path"
        class="flex items-center gap-3 p-2.5 bg-gray-50 dark:bg-white/5 rounded-xl group"
      >
        <!-- Thumbnail or Icon -->
        <button type="button" :aria-label="`预览附件 ${getFileName(path)}`"
          class="w-10 h-10 rounded-lg bg-gray-200 dark:bg-white/10 flex items-center justify-center overflow-hidden flex-shrink-0 cursor-pointer"
          @click="openPreview(path, $event)"
        >
          <img
            v-if="isImage(path) && previewUrls[path]"
            :src="previewUrls[path]"
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <component v-else :is="getFileIcon(path)" :size="20" class="text-gray-400" />
        </button>
        
        <!-- File Name -->
        <div class="flex-1 min-w-0">
          <div class="text-sm text-gray-700 dark:text-gray-300 truncate">
            {{ getFileName(path) }}
          </div>
        </div>
        
        <!-- Actions -->
        <div class="flex gap-1">
          <button
            type="button"
            :aria-label="`打开附件 ${getFileName(path)}`"
            class="p-1.5 text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition"
            @click="openPreview(path, $event)"
          >
            <Eye :size="16" />
          </button>
          <button
            type="button"
            :aria-label="`下载附件 ${getFileName(path)}`"
            class="p-1.5 text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/20 rounded-lg transition"
            @click="downloadFile(path)"
          >
            <Download :size="16" />
          </button>
          <button
            v-if="!disabled"
            type="button"
            :aria-label="`移除附件 ${getFileName(path)}`"
            class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition"
            @click="removeFile(path)"
          >
            <X :size="16" />
          </button>
        </div>
      </div>
    </div>
    
    <div v-if="failedUploads.length > 0" class="space-y-2">
      <div v-for="(file, index) in failedUploads" :key="index" role="alert"
        class="flex items-center gap-3 rounded-xl bg-red-50 p-2.5 text-sm dark:bg-red-900/20">
        <span class="min-w-0 flex-1 break-all text-red-600 dark:text-red-400">{{ file.name }} 上传失败</span>
        <button type="button" :disabled="uploading || !canUpload"
          :aria-label="`重试上传 ${file.name}`"
          class="min-h-11 shrink-0 rounded-lg px-3 text-blue-600 disabled:opacity-50 dark:text-blue-400"
          @click="uploadFiles([file])">重试</button>
      </div>
    </div>

    <!-- Upload Area -->
    <div
      v-if="canUpload"
      class="relative border-2 border-dashed rounded-xl p-4 text-center transition-all cursor-pointer"
      :class="[
        dragOver 
          ? 'border-blue-400 bg-blue-50 dark:bg-blue-900/20' 
          : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600',
        uploading ? 'opacity-50 pointer-events-none' : ''
      ]"
      @dragover="handleDragOver"
      @dragleave="handleDragLeave"
      @drop="handleDrop"
      @click="($refs.fileInput as HTMLInputElement)?.click()"
    >
      <input
        ref="fileInput"
        type="file"
        :disabled="uploading || disabled"
        aria-label="上传凭证附件"
        :accept="acceptTypes"
        multiple
        class="hidden"
        @change="handleFileSelect"
      />
      
      <div class="flex flex-col items-center gap-2">
        <div class="w-10 h-10 rounded-full bg-gray-100 dark:bg-white/10 flex items-center justify-center">
          <Upload :size="20" class="text-gray-400" />
        </div>
        <div class="text-sm text-gray-500 dark:text-gray-400">
          <span v-if="uploading">上传中...</span>
          <span v-else>点击或拖拽上传文件</span>
        </div>
        <div class="text-xs text-gray-400">
          最多 {{ maxFilesLimit }} 个文件
        </div>
      </div>
    </div>
    
    <!-- Image Preview Modal -->
    <AppDialog v-if="previewUrl" title="附件预览" :return-focus="previewTrigger" @close="closePreview">
      <img :src="previewUrl" alt="凭证图片预览" class="mx-auto max-w-full max-h-[70dvh] object-contain rounded-lg" />
    </AppDialog>
  </div>
</template>
