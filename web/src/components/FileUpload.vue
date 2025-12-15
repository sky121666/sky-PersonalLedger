<script setup lang="ts">
import { ref, computed } from 'vue'
import { Upload, X, FileText, Image, File, Download, Eye } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'

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

const authStore = useAuthStore()
const uploading = ref(false)
const dragOver = ref(false)
const previewUrl = ref<string | null>(null)

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

function getFileUrl(path: string) {
  const token = authStore.accessToken
  return `/uploads/${path}?token=${token}`
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
      
      const response = await fetch('/api/v1/upload', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${authStore.accessToken}`
        },
        body: formData
      })
      
      if (response.ok) {
        const result = await response.json()
        if (result.data?.path) {
          newPaths.push(result.data.path)
        }
      }
    }
    
    if (newPaths.length > 0) {
      const updatedFiles = [...files.value, ...newPaths]
      emit('update:modelValue', JSON.stringify(updatedFiles))
    }
  } catch (error) {
    console.error('Upload failed:', error)
  } finally {
    uploading.value = false
  }
}

async function removeFile(path: string) {
  try {
    const response = await fetch(`/api/v1/upload?path=${encodeURIComponent(path)}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${authStore.accessToken}`
      }
    })
    
    if (response.ok) {
      const updatedFiles = files.value.filter(f => f !== path)
      emit('update:modelValue', JSON.stringify(updatedFiles))
    }
  } catch (error) {
    console.error('Delete failed:', error)
  }
}

function openPreview(path: string) {
  if (isImage(path)) {
    previewUrl.value = getFileUrl(path)
  } else {
    window.open(getFileUrl(path), '_blank')
  }
}

function closePreview() {
  previewUrl.value = null
}

function downloadFile(path: string) {
  const link = document.createElement('a')
  link.href = `/api/v1/upload/download?path=${encodeURIComponent(path)}&token=${authStore.accessToken}`
  link.download = getFileName(path)
  link.click()
}
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
            v-if="isImage(path)" 
            :src="getFileUrl(path)" 
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
