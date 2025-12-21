import { describe, it, expect, jest, beforeAll, afterAll, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare global {
  // eslint-disable-next-line no-var
  var jwt: any
  // eslint-disable-next-line no-var
  var database: any
}

describe('UserService', () => {
  const originalJwt = global.jwt
  const originalDatabase = global.database

  beforeAll(() => {
    // Ensure globals exist if referenced by the module at runtime
    global.jwt = { decode: jest.fn() }
    global.database = { delete: jest.fn() }
  })

  afterAll(() => {
    global.jwt = originalJwt
    global.database = originalDatabase
  })

  beforeEach(() => {
    global.jwt.decode = jest.fn(() => ({ sub: 'user' }))
    global.database.delete = jest.fn()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false for empty password', () => {
      const svc = new UserService()
      expect(svc.authenticate('any', '')).toBe(false)
    })

    it('returns false when password length is less than 4 (e.g., 3)', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '123')).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '1234')).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', 'longpassword')).toBe(true)
    })

    it('ignores username and bases result solely on password length', () => {
      const svc = new UserService()
      expect(svc.authenticate('alice', '1234')).toBe(true)
      expect(svc.authenticate('bob', '1234')).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with users/<id> path', () => {
      const svc = new UserService()
      svc.deleteUser('u123')
      expect(global.database.delete).toHaveBeenCalledTimes(1)
      expect(global.database.delete).toHaveBeenCalledWith('users/u123')
    })

    it('returns undefined (void) on success', () => {
      const svc = new UserService()
      const result = svc.deleteUser('u999')
      expect(result).toBeUndefined()
    })

    it('propagates errors thrown by database.delete', () => {
      const svc = new UserService()
      const err = new Error('db error')
      ;(global.database.delete as jest.Mock).mockImplementation(() => { throw err })
      expect(() => svc.deleteUser('uerr')).toThrow(err)
    })
  })

  describe('isAdmin', () => {
    it('returns true for user with role "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('uses loose equality and returns true for new String("admin")', () => {
      const svc = new UserService()
      // eslint-disable-next-line no-new-wrappers
      const wrapped = new String('admin') as any
      expect(svc.isAdmin({ role: wrapped })).toBe(true)
    })

    it('is case-sensitive and returns false for "ADMIN"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'ADMIN' })).toBe(false)
    })

    it('returns false when role is missing or not equal to "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({})).toBe(false)
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin(null as any)).toBe(false)
      expect(svc.isAdmin({ role: 123 })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      const svc = new UserService()
      ;(global.jwt.decode as jest.Mock).mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('tok1')).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      ;(global.jwt.decode as jest.Mock).mockReturnValue(null)
      expect(svc.validateToken('tok2')).toBe(false)
    })

    it('passes the token argument to jwt.decode', () => {
      const svc = new UserService()
      ;(global.jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'some.token.value'
      svc.validateToken(token)
      expect(global.jwt.decode).toHaveBeenCalledTimes(1)
      expect(global.jwt.decode).toHaveBeenCalledWith(token)
    })

    it('returns true even if decoded token contains exp suggesting expiration is ignored', () => {
      const svc = new UserService()
      ;(global.jwt.decode as jest.Mock).mockReturnValue({ exp: 0 })
      expect(svc.validateToken('expired?')).toBe(true)
    })

    it('multiple calls invoke jwt.decode each time', () => {
      const svc = new UserService()
      ;(global.jwt.decode as jest.Mock).mockReturnValue({ a: 1 })
      expect(svc.validateToken('t1')).toBe(true)
      expect(svc.validateToken('t2')).toBe(true)
      expect(global.jwt.decode).toHaveBeenCalledTimes(2)
      expect(global.jwt.decode).toHaveBeenNthCalledWith(1, 't1')
      expect(global.jwt.decode).toHaveBeenNthCalledWith(2, 't2')
    })
  })

  describe('hardcoded secret fields presence (runtime behavior)', () => {
    it('exposes ADMIN_PASSWORD at runtime via property access', () => {
      const svc: any = new UserService()
      expect(svc.ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY at runtime via property access', () => {
      const svc: any = new UserService()
      expect(svc.API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})