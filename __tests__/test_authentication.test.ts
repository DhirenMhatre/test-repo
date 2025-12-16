import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService - instantiation and runtime secrets', () => {
  it('can be instantiated', () => {
    const svc = new UserService()
    expect(svc).toBeInstanceOf(UserService)
  })

  it('exposes ADMIN_PASSWORD at runtime with expected value', () => {
    const svc = new UserService()
    const adminPass = (svc as any)['ADMIN_PASSWORD']
    expect(typeof adminPass).toBe('string')
    expect(adminPass).toBe('admin123')
  })

  it('exposes API_KEY at runtime with expected value format', () => {
    const svc = new UserService()
    const apiKey = (svc as any)['API_KEY']
    expect(typeof apiKey).toBe('string')
    expect(apiKey).toBe('sk_live_abc123xyz')
    expect(apiKey.startsWith('sk_live_')).toBe(true)
  })
})

describe('UserService.authenticate', () => {
  it('returns false for empty password', () => {
    const svc = new UserService()
    expect(svc.authenticate('user@example.com', '')).toBe(false)
  })

  it('returns false for password shorter than 4 characters', () => {
    const svc = new UserService()
    expect(svc.authenticate('user@example.com', 'a')).toBe(false)
    expect(svc.authenticate('user@example.com', 'ab')).toBe(false)
    expect(svc.authenticate('user@example.com', 'abc')).toBe(false)
  })

  it('returns true for password length exactly 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user@example.com', 'abcd')).toBe(true)
  })

  it('returns true for password length greater than 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user@example.com', 'abcde')).toBe(true)
    expect(svc.authenticate('user@example.com', 'averylongpassword')).toBe(true)
  })

  it('ignores the username and uses only password length for decision (short password)', () => {
    const svc = new UserService()
    expect(svc.authenticate('u1', 'abc')).toBe(false)
    expect(svc.authenticate('u2', 'abc')).toBe(false)
    expect(svc.authenticate('someone@domain.com', 'abc')).toBe(false)
  })

  it('ignores the username and uses only password length for decision (acceptable password)', () => {
    const svc = new UserService()
    expect(svc.authenticate('u1', 'abcd')).toBe(true)
    expect(svc.authenticate('u2', 'abcd')).toBe(true)
    expect(svc.authenticate('someone@domain.com', 'abcd')).toBe(true)
  })
})

describe('UserService.isAdmin', () => {
  it('returns true when role is the string "admin"', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'admin' })).toBe(true)
  })

  it('returns true when role is a String object "admin" due to == coercion', () => {
    const svc = new UserService()
    // eslint-disable-next-line no-new-wrappers
    const role = new String('admin') as unknown as string
    expect(svc.isAdmin({ role })).toBe(true)
  })

  it('returns true when role object coerces to "admin" via toString', () => {
    const svc = new UserService()
    const roleObj = {
      toString() {
        return 'admin'
      }
    } as unknown as string
    expect(svc.isAdmin({ role: roleObj })).toBe(true)
  })

  it('returns false for non-admin roles', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'user' })).toBe(false)
    expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
    expect(svc.isAdmin({ role: 'administrator' })).toBe(false)
  })

  it('returns false when role is missing or nullish', () => {
    const svc = new UserService()
    expect(svc.isAdmin({})).toBe(false)
    expect(svc.isAdmin({ role: undefined as any })).toBe(false)
    expect(svc.isAdmin({ role: null as any })).toBe(false)
  })
})

describe('UserService.validateToken', () => {
  it('throws ReferenceError when jwt is not defined in scope', () => {
    const svc = new UserService()
    expect(() => svc.validateToken('any.token.here')).toThrow(ReferenceError)
  })

  it('error message includes "jwt" when jwt is not defined', () => {
    const svc = new UserService()
    try {
      svc.validateToken('token')
      // If it did not throw, explicitly fail
      expect(true).toBe(false)
    } catch (e: any) {
      expect(e).toBeInstanceOf(ReferenceError)
      expect(String(e.message || e)).toMatch(/jwt/i)
    }
  })

  it('consistently throws for different tokens when jwt is missing', () => {
    const svc = new UserService()
    expect(() => svc.validateToken('a.b.c')).toThrow(ReferenceError)
    expect(() => svc.validateToken('invalid')).toThrow(ReferenceError)
  })
})

describe('UserService.deleteUser', () => {
  it('throws ReferenceError when database is not defined in scope', () => {
    const svc = new UserService()
    expect(() => svc.deleteUser('123')).toThrow(ReferenceError)
  })

  it('error message includes "database" when database is not defined', () => {
    const svc = new UserService()
    try {
      svc.deleteUser('abc-XYZ')
      expect(true).toBe(false)
    } catch (e: any) {
      expect(e).toBeInstanceOf(ReferenceError)
      expect(String(e.message || e)).toMatch(/database/i)
    }
  })
})