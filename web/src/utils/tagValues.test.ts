import { describe, expect, it } from 'vitest'

import { encodeTransactionTags, parseTransactionTags } from './tagValues'

describe('transaction tag values', () => {
  it('parses JSON and legacy comma-separated values without duplicates', () => {
    expect(parseTransactionTags('["餐饮", " 餐饮 ", "报销"]')).toEqual(['报销', '餐饮'])
    expect(parseTransactionTags('餐饮, 报销,餐饮')).toEqual(['报销', '餐饮'])
  })

  it('encodes a normalized JSON array for the backend contract', () => {
    expect(encodeTransactionTags([' 餐饮 ', '报销', '餐饮'])).toBe('["报销","餐饮"]')
  })

  it('rejects malformed or unsupported values safely', () => {
    expect(parseTransactionTags('{"name":"餐饮"}')).toEqual([])
    expect(parseTransactionTags(null)).toEqual([])
  })
})
