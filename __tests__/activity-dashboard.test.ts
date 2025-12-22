import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
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

jest.mock('react-use', () => ({
  ...jest.requireActual('react-use'),
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

jest.mock('next/navigation', () => ({
  ...jest.requireActual('next/navigation'),
  const redirect = jest.fn()
  return {
    useRouter: () => ({ push: jest.fn(), replace: jest.fn(), prefetch: jest.fn(), back: jest.fn() }),
    usePathname: () => '/',
    useSearchParams: () => ({ get: () => null, toString: () => '' }),
    redirect,
  }
})

jest.mock('next/router', () => ({
  ...jest.requireActual('next/router'),
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

  it('react-use useMedia mock returns false and is called', async () => {
    const { useMedia } = await import('react-use')
    const res = useMedia('(min-width: 768px)')
    expect(res).toBe(false)
    expect((useMedia as unknown as jest.Mock).mock.calls.length).toBe(1)
    expect((useMedia as unknown as jest.Mock).mock.calls[0][0]).toBe('(min-width: 768px)')
  })

  it('next/navigation router push and redirect record calls', async () => {
    const { useRouter, redirect } = await import('next/navigation')
    const router = useRouter()
    router.push('/test')
    ;(redirect as jest.Mock)('/target')
    expect((router.push as jest.Mock).mock.calls[0][0]).toBe('/test')
    expect((redirect as jest.Mock).mock.calls[0][0]).toBe('/target')
  })
})