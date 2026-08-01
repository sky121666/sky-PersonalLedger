function twoDigits(value: number): string {
  return value.toString().padStart(2, '0')
}

export function formatLocalDate(date = new Date()): string {
  return `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`
}

export function formatLocalMonth(date = new Date()): string {
  return `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}`
}
