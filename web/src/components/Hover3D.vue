<script setup lang="ts">
import { ref, computed } from 'vue'

const props = defineProps<{
  intensity?: number
  scale?: number
  shine?: boolean
}>()

const cardRef = ref<HTMLElement | null>(null)
const isHovering = ref(false)
const rotateX = ref(0)
const rotateY = ref(0)
const shineX = ref(50)
const shineY = ref(50)

const intensityValue = computed(() => props.intensity ?? 15)
const hoverScale = computed(() => props.scale ?? 1.02)

function handleMouseMove(e: MouseEvent) {
  if (!cardRef.value) return
  
  const rect = cardRef.value.getBoundingClientRect()
  const centerX = rect.left + rect.width / 2
  const centerY = rect.top + rect.height / 2
  
  const mouseX = e.clientX - centerX
  const mouseY = e.clientY - centerY
  
  rotateY.value = (mouseX / (rect.width / 2)) * intensityValue.value
  rotateX.value = -(mouseY / (rect.height / 2)) * intensityValue.value
  
  shineX.value = ((e.clientX - rect.left) / rect.width) * 100
  shineY.value = ((e.clientY - rect.top) / rect.height) * 100
}

function handleMouseEnter() {
  isHovering.value = true
}

function handleMouseLeave() {
  isHovering.value = false
  rotateX.value = 0
  rotateY.value = 0
  shineX.value = 50
  shineY.value = 50
}
</script>

<template>
  <div
    ref="cardRef"
    class="hover-3d-wrapper"
    :style="{
      transform: isHovering 
        ? `perspective(1200px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(${hoverScale}, ${hoverScale}, ${hoverScale})`
        : 'perspective(1200px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)',
      transition: isHovering ? 'transform 0.08s ease-out' : 'transform 0.4s cubic-bezier(0.23, 1, 0.32, 1)'
    }"
    @mousemove="handleMouseMove"
    @mouseenter="handleMouseEnter"
    @mouseleave="handleMouseLeave"
  >
    <slot />
    <!-- Primary shine -->
    <div 
      v-if="shine !== false"
      class="shine-overlay"
      :style="{
        background: `radial-gradient(ellipse 80% 50% at ${shineX}% ${shineY}%, rgba(255,255,255,0.35) 0%, rgba(255,255,255,0.1) 30%, transparent 70%)`,
        opacity: isHovering ? 1 : 0
      }"
    />
    <!-- Secondary highlight -->
    <div 
      v-if="shine !== false"
      class="shine-overlay-secondary"
      :style="{
        background: `linear-gradient(${135 + rotateY}deg, rgba(255,255,255,0.15) 0%, transparent 50%)`,
        opacity: isHovering ? 1 : 0
      }"
    />
  </div>
</template>

<style scoped>
.hover-3d-wrapper {
  position: relative;
  transform-style: preserve-3d;
  will-change: transform;
}

.shine-overlay {
  position: absolute;
  inset: 0;
  pointer-events: none;
  border-radius: inherit;
  transition: opacity 0.25s ease;
  z-index: 20;
  mix-blend-mode: overlay;
}

.shine-overlay-secondary {
  position: absolute;
  inset: 0;
  pointer-events: none;
  border-radius: inherit;
  transition: opacity 0.25s ease, background 0.1s ease;
  z-index: 19;
}
</style>
