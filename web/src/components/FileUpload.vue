<script setup lang="ts">
import { ref, computed, onBeforeUnmount, watch } from 'vue'
import { Upload, X, FileText, Image, File, Download, Eye } from 'lucide-vue-next'
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
}>()

const uploading = ref(false)
const dragOver = ref(false)
const previewUrl = ref<string | null>(null)
const previewUrls = ref<Record<string, string>>({})
const objectUrls = new Map<string, string>()

const maxFilesLimit = computed(() => props.maxFiles || 5)
const acceptTypes = computed(() => props.accept || 'image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt')

const files = computed<string[]>(() => {
  if (!props.modelValue) return []
  try {
    return JSON.parse(props.modelValue)
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

async function uploadFiles(fileList: File[]) {
  if (!canUpload.value) return
  
  const remainingSlots = maxFilesLimit.value - files.value.length
  const filesToUpload = fileList.slice(0, remainingSlots)
  
  uploading.value = true
  
  try {
    const newPaths: string[] = []
    
    for (const file of filesToUpload) {
      const formData = new FormData()
      formData.append('file', file)
      formData.append('category', props.category)
      formData.append('ref_id', props.refId)

      const result = await fileApi.upload(formData)
      if (result.path) {
        newPaths.push(result.path)
      }
    }
    
    if (newPaths.length > 0) {
      const updatedFiles = [...files.value, ...newPaths]
      emit('update:modelValue', JSON.stringify(updatedFiles))
    }
  } catch (error) {
    console.error('Upload failed:', error)
    toast.error('上传失败')
  } finally {
    uploading.value = false
  }
}

async function removeFile(path: string) {
  try {
    await fileApi.delete(path)
    const updatedFiles = files.value.filter(f => f !== path)
    emit('update:modelValue', JSON.stringify(updatedFiles))
  } catch (error) {
    console.error('Delete failed:', error)
    toast.error('删除失败')
  }
}

async function openPreview(path: string) {
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
        <div 
          class="w-10 h-10 rounded-lg bg-gray-200 dark:bg-white/10 flex items-center justify-center overflow-hidden flex-shrink-0 cursor-pointer"
          @click="openPreview(path)"
        >
          <img
            v-if="isImage(path) && previewUrls[path]"
            :src="previewUrls[path]"
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <component v-else :is="getFileIcon(path)" :size="20" class="text-gray-400" />
        </div>
        
        <!-- File Name -->
        <div class="flex-1 min-w-0">
          <div class="text-sm text-gray-700 dark:text-gray-300 truncate">
            {{ getFileName(path) }}
          </div>
        </div>
        
        <!-- Actions -->
        <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            type="button"
            class="p-1.5 text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition"
            @click="openPreview(path)"
          >
            <Eye :size="16" />
          </button>
          <button
            type="button"
            class="p-1.5 text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/20 rounded-lg transition"
            @click="downloadFile(path)"
          >
            <Download :size="16" />
          </button>
          <button
            v-if="!disabled"
            type="button"
            class="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition"
            @click="removeFile(path)"
          >
            <X :size="16" />
          </button>
        </div>
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
    <Teleport to="body">
      <div
        v-if="previewUrl"
        class="fixed inset-0 z-[100] bg-black/80 flex items-center justify-center p-4"
        @click="closePreview"
      >
        <button
          class="absolute top-4 right-4 p-2 bg-white/10 hover:bg-white/20 rounded-full text-white transition"
          @click.stop="closePreview"
        >
          <X :size="24" />
        </button>
        <img
          :src="previewUrl"
          class="max-w-full max-h-full object-contain rounded-lg"
          @click.stop
        />
      </div>
    </Teleport>
  </div>
</template>
