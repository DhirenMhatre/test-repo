import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare const global: any

describe('UserService', () => {
  let svc: UserService

  beforeEach(() => {
    global.database = { delete: jest.fn() }
    global.jwt = { decode: jest.fn() }
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete global.database
    delete global.jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      expect(svc.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true when password length is 4', () => {
      expect(svc.authenticate('user', 'abcd')).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      expect(svc.authenticate('user', 'abcdef')).toBe(true)
    })

    it('ignores username value when authenticating', () => {
      expect(svc.authenticate('alice', 'abcd')).toBe(true)
      expect(svc.authenticate('bob', 'abcd')).toBe(true)
    })

    it('returns false for empty password', () => {
      expect(svc.authenticate('user', '')).toBe(false)
    })

    it('returns true when password is non-string with no length (coercion leads to undefined < 4 -> false)', () => {
      const nonStringPassword = 5 as unknown as string
      expect(svc.authenticate('user', nonStringPassword)).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct path', () => {
      svc.deleteUser('123')
      expect(global.database.delete).toHaveBeenCalledTimes(1)
      expect(global.database.delete).toHaveBeenCalledWith('users/123')
    })

    it('propagates errors thrown by database.delete', () => {
      global.database.delete.mockImplementation(() => {
        throw new Error('boom')
      })
      expect(() => svc.deleteUser('999')).toThrow('boom')
      expect(global.database.delete).toHaveBeenCalledWith('users/999')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin" string', () => {
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when role is not "admin" or missing', () => {
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({})).toBe(false)
      expect(svc.isAdmin({ role: undefined })).toBe(false)
    })

    it('returns true when role is a String object wrapper equal to "admin" (== allows coercion)', () => {
      const role = new (String as any)('admin')
      expect(svc.isAdmin({ role })).toBe(true)
    })

    it('returns true when role object coerces to "admin" via toString (== allows object coercion)', () => {
      const roleObj = { toString: () => 'admin' }
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a payload object', () => {
      global.jwt.decode.mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('token')).toBe(true)
      expect(global.jwt.decode).toHaveBeenCalledWith('token')
    })

    it('returns true when jwt.decode returns a falsy non-null value (e.g., false)', () => {
      global.jwt.decode.mockReturnValue(false)
      expect(svc.validateToken('token')).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      global.jwt.decode.mockReturnValue(null)
      expect(svc.validateToken('bad-token')).toBe(false)
    })

    it('propagates errors if jwt.decode throws', () => {
      global.jwt.decode.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => svc.validateToken('token')).toThrow('decode error')
    })
  })

  describe('hardcoded secret fields (runtime presence)', () => {
    it('exposes ADMIN_PASSWORD value on instance', () => {
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY value on instance', () => {
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})