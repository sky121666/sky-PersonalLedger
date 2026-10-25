export function chartAxisLimit(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 1
  const padded = value * 1.08
  const unit = 10 ** Math.floor(Math.log10(padded))
  const factor = [1, 2, 2.5, 5, 10].find(step => step * unit >= padded) ?? 10
  return factor * unit
}

export function chartBarPercent(value: number, limit: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(limit) || value <= 0 || limit <= 0) return 0
  return Math.min(value / limit * 100, 100)
}
