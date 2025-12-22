import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns') as Record<string, unknown>
  return {
    ...actual,
    format: jest.fn((_date: Date | number, _fmt?: string) => '2024-01-01'),
    subMonths: jest.fn((_date: Date | number, _n: number) => new Date('2024-01-01')),
  }
})

jest.mock('react-use', () => {
  const actual = jest.requireActual('react-use') as Record<string, unknown>
  return {
    ...actual,
    useMedia: jest.fn(() => false),
  }
})

jest.mock('next/navigation', () => {
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

jest.mock('next/router', () => {
  const actual = jest.requireActual('next/router') as Record<string, unknown>
  return { ...actual }
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('mocks', () => {
  it('date-fns mocks are deterministic', async () => {
    const mod = await import('date-fns')
    const format = mod.format as unknown as jest.Mock
    const subMonths = mod.subMonths as unknown as jest.Mock

    const d = new Date('2023-05-15')

    expect(format(d, 'yyyy-MM-dd')).toBe('2024-01-01')

    const result = subMonths(d, 3)
    expect(result).toEqual(new Date('2024-01-01'))

    expect(format.mock.calls.length).toBeGreaterThan(0)
    expect(subMonths.mock.calls.length).toBeGreaterThan(0)
  })

  it('react-use useMedia mock returns false and is called', async () => {
    const mod = await import('react-use')
    const useMedia = mod.useMedia as unknown as jest.Mock

    const res = useMedia('(min-width: 768px)')

    expect(res).toBe(false)
    expect(useMedia.mock.calls.length).toBe(1)
    expect(useMedia.mock.calls[0][0]).toBe('(min-width: 768px)')
  })

  it('next/navigation router push and redirect record calls', async () => {
    const mod = await import('next/navigation')
    const useRouter = mod.useRouter as unknown as () => { push: jest.Mock }
    const redirect = mod.redirect as unknown as jest.Mock

    const router = useRouter()

    router.push('/test')
    redirect('/target')

    expect((router.push as unknown as jest.Mock).mock.calls[0][0]).toBe('/test')
    expect(redirect.mock.calls[0][0]).toBe('/target')
  })

  it('next/router module loads (no-op mock)', async () => {
    const mod = await import('next/router')
    expect(mod).toBeTruthy()
  })
})