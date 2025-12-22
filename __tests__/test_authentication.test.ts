import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare const database: { delete: (path: string) => void }
declare const jwt: { decode: (token: string) => any }

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length is 0', () => {
      expect(service.authenticate('user', '')).toBe(false)
    })

    it('returns false when password length is 3', () => {
      expect(service.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true when password length is 4', () => {
      expect(service.authenticate('user', 'abcd')).toBe(true)
    })

    it('returns true when password length is long', () => {
      expect(service.authenticate('user', 'verylongpassword')).toBe(true)
    })

    it('does not depend on username value for short password (still false)', () => {
      expect(service.authenticate('admin', '123')).toBe(false)
      expect(service.authenticate('', '123')).toBe(false)
      expect(service.authenticate('someone', '123')).toBe(false)
    })

    it('does not depend on username value for valid password (still true)', () => {
      expect(service.authenticate('admin', '1234')).toBe(true)
      expect(service.authenticate('', '1234')).toBe(true)
      expect(service.authenticate('someone', '1234')).toBe(true)
    })
  })

  describe('deleteUser', () => {
    beforeEach(() => {
      ;(globalThis as any).database = {
        delete: jest.fn()
      }
    })

    it('calls database.delete with users/{userId}', () => {
      service.deleteUser('123')
      expect((globalThis as any).database.delete).toHaveBeenCalledTimes(1)
      expect((globalThis as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('passes through userId as-is (no sanitization/encoding)', () => {
      service.deleteUser('abc/def')
      expect((globalThis as any).database.delete).toHaveBeenCalledWith('users/abc/def')
    })

    it('passes through empty userId (still calls database.delete)', () => {
      service.deleteUser('')
      expect((globalThis as any).database.delete).toHaveBeenCalledWith('users/')
    })

    it('does not return a value (undefined)', () => {
      const result = service.deleteUser('999')
      expect(result).toBeUndefined()
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      expect(service.isAdmin({ role: 'user' })).toBe(false)
      expect(service.isAdmin({ role: 'administrator' })).toBe(false)
      expect(service.isAdmin({ role: 'Admin' })).toBe(false)
    })

    it('uses loose equality: returns true when role is an object coercing to "admin"', () => {
      const roleObj = {
        toString: () => 'admin',
        valueOf: () => 'admin'
      }
      expect(service.isAdmin({ role: roleObj as any })).toBe(true)
    })

    it('returns false when role is null', () => {
      expect(service.isAdmin({ role: null })).toBe(false)
    })

    it('returns false when role is undefined', () => {
      expect(service.isAdmin({ role: undefined })).toBe(false)
    })
  })

  describe('validateToken', () => {
    beforeEach(() => {
      ;(globalThis as any).jwt = {
        decode: jest.fn()
      }
    })

    it('calls jwt.decode with the provided token', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockReturnValue({ sub: 'u1' })
      const result = service.validateToken('token123')
      expect((globalThis as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((globalThis as any).jwt.decode).toHaveBeenCalledWith('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockReturnValue(null)
      expect(service.validateToken('badtoken')).toBe(false)
    })

    it('returns true when jwt.decode returns an empty object', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockReturnValue({})
      expect(service.validateToken('token')).toBe(true)
    })

    it('returns true when jwt.decode returns 0 (non-null)', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockReturnValue(0)
      expect(service.validateToken('token')).toBe(true)
    })

    it('returns true when jwt.decode returns undefined (non-null check only)', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockReturnValue(undefined)
      expect(service.validateToken('token')).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;((globalThis as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => service.validateToken('token')).toThrow('decode failed')
    })
  })

  describe('class runtime characteristics', () => {
    it('creates independent instances that share the same method behavior', () => {
      const s1 = new UserService()
      const s2 = new UserService()

      expect(s1.authenticate('u', '123')).toBe(false)
      expect(s2.authenticate('u', '123')).toBe(false)
      expect(s1.authenticate('u', '1234')).toBe(true)
      expect(s2.authenticate('u', '1234')).toBe(true)
    })

    it('does not expose hardcoded secrets as enumerable properties on the instance', () => {
      const keys = Object.keys(service as any)
      expect(keys).not.toContain('ADMIN_PASSWORD')
      expect(keys).not.toContain('API_KEY')
    })
  })
})