<template>
  <div class="min-h-screen bg-gradient-to-br from-slate-100 to-blue-50 flex items-center justify-center p-6">
    <div class="w-full max-w-lg bg-white rounded-2xl shadow-xl p-8">

      <!-- 標題 -->
      <div class="text-center mb-8">
        <h1 class="text-3xl font-bold text-gray-800 mb-1">🎙️ AI 會議記錄助手</h1>
        <p class="text-gray-400 text-sm">上傳錄音檔，自動產生 Word 格式會議記錄</p>
      </div>

      <!-- 上傳區 -->
      <div
        class="border-2 border-dashed rounded-xl p-10 text-center cursor-pointer transition-all duration-200"
        :class="isDragging
          ? 'border-blue-400 bg-blue-50 scale-[1.01]'
          : 'border-gray-200 hover:border-blue-300 hover:bg-gray-50'"
        @dragover.prevent="isDragging = true"
        @dragleave.prevent="isDragging = false"
        @drop.prevent="onDrop"
        @click="triggerInput"
      >
        <input
          ref="inputRef"
          type="file"
          accept="audio/*"
          class="hidden"
          @change="onFileChange"
        />

        <div v-if="!file" class="flex flex-col items-center gap-3 text-gray-400">
          <svg class="w-14 h-14" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
              d="M12 18.75a6 6 0 006-6v-1.5m-6 7.5a6 6 0 01-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 01-3-3V4.5a3 3 0 116 0v8.25a3 3 0 01-3 3z" />
          </svg>
          <p class="text-base font-medium text-gray-500">拖曳錄音檔到此處</p>
          <p class="text-xs">或點擊選擇檔案（MP3、WAV、M4A、OGG…）</p>
        </div>

        <!-- 已選檔案 -->
        <div v-else class="flex items-center gap-3 bg-blue-50 rounded-lg px-4 py-3" @click.stop>
          <svg class="w-6 h-6 text-blue-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
          </svg>
          <span class="text-sm text-gray-700 flex-1 truncate text-left">{{ file.name }}</span>
          <span class="text-xs text-gray-400 shrink-0">{{ fileSizeMB }}</span>
          <button
            class="ml-2 text-xs font-semibold text-white bg-red-400 hover:bg-red-500 px-2 py-1 rounded transition-colors"
            @click.stop="removeFile"
          >
            移除
          </button>
        </div>
      </div>

      <!-- 開始整理按鈕 -->
      <button
        class="mt-6 w-full py-3 rounded-xl font-semibold text-white text-base flex items-center justify-center gap-2 transition-all duration-200"
        :class="canSubmit
          ? 'bg-blue-500 hover:bg-blue-600 shadow-md hover:shadow-lg'
          : 'bg-gray-300 cursor-not-allowed'"
        :disabled="!canSubmit"
        @click="submit"
      >
        <svg v-if="loading" class="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
        </svg>
        <span>{{ loading ? 'AI 正在聆聽中...' : '✨ 開始整理' }}</span>
      </button>

      <!-- 成功提示 -->
      <div v-if="downloaded" class="mt-4 flex items-center gap-2 text-green-600 bg-green-50 rounded-lg px-4 py-3 text-sm">
        <svg class="w-5 h-5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
        </svg>
        會議記錄已產生，正在下載 <strong>meeting_minutes.docx</strong>
      </div>

    </div>
  </div>
</template>

<script setup>
const inputRef = ref(null)
const file = ref(null)
const isDragging = ref(false)
const loading = ref(false)
const downloaded = ref(false)

const fileSizeMB = computed(() =>
  file.value ? `${(file.value.size / 1024 / 1024).toFixed(2)} MB` : ''
)

const canSubmit = computed(() => !!file.value && !loading.value)

function triggerInput() {
  inputRef.value?.click()
}

function onFileChange(e) {
  const f = e.target.files?.[0]
  if (f) setFile(f)
}

function onDrop(e) {
  isDragging.value = false
  const f = e.dataTransfer.files?.[0]
  if (f && f.type.startsWith('audio/')) {
    setFile(f)
  } else {
    alert('請上傳音訊格式檔案（MP3、WAV、M4A 等）')
  }
}

function setFile(f) {
  file.value = f
  downloaded.value = false
}

function removeFile() {
  file.value = null
  downloaded.value = false
  if (inputRef.value) inputRef.value.value = ''
}

async function submit() {
  if (!canSubmit.value) return
  loading.value = true
  downloaded.value = false

  try {
    const formData = new FormData()
    formData.append('file', file.value)

    const blob = await $fetch('/api/generate', {
      method: 'POST',
      body: formData,
      responseType: 'blob'
    })

    // 觸發下載
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'meeting_minutes.docx'
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)

    downloaded.value = true
  } catch (e) {
    const msg = await e?.data?.text?.() || e?.message || '發生錯誤，請稍後再試'
    alert(`❌ 錯誤：${msg}`)
  } finally {
    loading.value = false
  }
}
</script>
