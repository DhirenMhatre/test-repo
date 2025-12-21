import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { format, subMonths } from 'date-fns'
import { useMedia } from 'react-use'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    format: jest.fn((_date: Date | number, _fmt?: string) => '2024-01-01'),
    subMonths: jest.fn((_date: Date | number, _n: number) => new Date('2024-01-01')),
  }
})

jest.mock('react-use', () => {
  const actual = jest.requireActual('react-use')
  return {
    ...actual,
    useMedia: jest.fn(() => false),
  }
})

jest.mock('next/navigation', () => {
  return {
    useRouter: () => ({ push: jest.fn(), replace: jest.fn(), prefetch: jest.fn(), back: jest.fn() }),
    usePathname: () => '/',
    useSearchParams: () => ({ get: () => null, toString: () => '' }),
    redirect: jest.fn(),
  }
})

jest.mock('next/router', () => {
  return {}
})

jest.mock('next/config', () => {
  return () => ({
    publicRuntimeConfig: {},
    serverRuntimeConfig: {},
  })
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('mocks', () => {
  it('date-fns mocks are deterministic', () => {
    const d = new Date('2023-05-15T00:00:00.000Z')
    expect(format(d, 'yyyy-MM-dd')).toBe('2024-01-01')
    const d2 = subMonths(d, 6)
    expect(d2).toEqual(new Date('2024-01-01'))
    expect(format(d2, 'yyyy-MM-dd')).toBe('2024-01-01')
  })

  it('react-use useMedia is mocked to false', () => {
    expect(useMedia('(min-width: 768px)')).toBe(false)
  })
})