import { describe, it, expect, jest, afterEach } from '@jest/globals'

// Mock date-fns with stable implementations while preserving other exports when possible
jest.mock('date-fns', () => {
  try {
    const actual = jest.requireActual('date-fns')
    return {
      ...actual,
      format: jest.fn((_date: Date | number, _fmt?: string) => '2024-01-01'),
      subMonths: jest.fn((_date: Date | number, _n: number) => new Date('2024-01-01')),
    }
  } catch {
    return {
      format: jest.fn((_date: Date | number, _fmt?: string) => '2024-01-01'),
      subMonths: jest.fn((_date: Date | number, _n: number) => new Date('2024-01-01')),
    }
  }
})

// Mock react-use while preserving actual exports when available
jest.mock('react-use', () => {
  try {
    const actual = jest.requireActual('react-use')
    return {
      ...actual,
      useMedia: jest.fn(() => false),
    }
  } catch {
    return {
      useMedia: jest.fn(() => false),
    }
  }
})

// Common Next.js mocks in case the module under test imports them
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

afterEach(() => {
  jest.clearAllMocks()
})

describe('mocks', () => {
  it('date-fns mocks are deterministic', async () => {
    const { format, subMonths } = await import('date-fns')
    const d = new Date('2023-05-15')
    expect(format(d, 'yyyy-MM-dd')).toBe('2024-01-01')
    const result = subMonths(d, 3)
    expect(result).toEqual(new Date('2024-01-01'))
    expect((format as unknown as jest.Mock).mock.calls.length).toBeGreaterThan(0)
    expect((subMonths as unknown as jest.Mock).mock.calls.length).toBeGreaterThan(0)
  })

  it('react-use useMedia mock returns false', async () => {
    const { useMedia } = await import('react-use')
    expect(useMedia('(min-width: 768px)')).toBe(false)
  })

  it('next/navigation mocks are callable', async () => {
    const { useRouter, redirect } = await import('next/navigation')
    const router = useRouter()
    router.push('/test')
    expect(typeof router.push).toBe('function')
    expect(typeof redirect).toBe('function')
  })
})