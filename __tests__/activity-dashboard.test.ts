import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  const actual = jest.requireActual('date-fns') as Record<string, unknown>
  return {
    ...actual,
    format: jest.fn((_date: Date | number, _fmt?: string) => '2024-01-01'),
    subMonths: jest.fn((_date: Date | number, _n: number) => new Date('2024-01-01')),
  }
})

jest.mock('react-use', () => ({
  ...jest.requireActual('react-use'),
  const actual = jest.requireActual('react-use') as Record<string, unknown>
  return {
    ...actual,
    useMedia: jest.fn(() => false),
  }
})

jest.mock('next/navigation', () => ({
  ...jest.requireActual('next/navigation'),
  const actual = jest.requireActual('next/navigation') as Record<string, unknown>
  const redirect = jest.fn()
  const push = jest.fn()
  const replace = jest.fn()
  const prefetch = jest.fn()
  const back = jest.fn()

  return {
    ...actual,
    useRouter: () => ({ push, replace, prefetch, back }),
    usePathname: () => '/',
    useSearchParams: () => ({ get: () => null, toString: () => '' }),
    redirect,
  }
})

jest.mock('next/router', () => ({
  ...jest.requireActual('next/router'),
  const actual = jest.requireActual('next/router') as Record<string, unknown>
  return { ...actual }
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('mocks', () => {
  it('date-fns format and subMonths return deterministic values', async () => {
    const mod = await import('date-fns')
    const format = mod.format as unknown as jest.Mock
    const subMonths = mod.subMonths as unknown as jest.Mock

    const d = new Date('2023-05-15')

    expect(format(d, 'yyyy-MM-dd')).toBe('2024-01-01')

    const result = subMonths(d, 3)
    expect(result).toEqual(new Date('2024-01-01'))
  })

  it('react-use useMedia returns false', async () => {
    const mod = await import('react-use')
    const useMedia = mod.useMedia as unknown as jest.Mock

    expect(useMedia('(min-width: 768px)')).toBe(false)
  })

  it('next/navigation useRouter push and redirect can be invoked', async () => {
    const mod = await import('next/navigation')
    const useRouter = mod.useRouter as unknown as () => { push: jest.Mock }
    const redirect = mod.redirect as unknown as jest.Mock

    const router = useRouter()
    router.push('/test')
    redirect('/target')

    expect((router.push as unknown as jest.Mock).mock.calls[0][0]).toBe('/test')
    expect(redirect.mock.calls[0][0]).toBe('/target')
  })
})