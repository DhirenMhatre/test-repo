import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let originalJwt: any
  let originalDatabase: any

  beforeEach(() => {
    originalJwt = (global as any).jwt
    originalDatabase = (global as any).database
    ;(global as any).jwt = { decode: jest.fn() }
    ;(global as any).database = { delete: jest.fn() }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    ;(global as any).jwt = originalJwt
    ;(global as any).database = originalDatabase
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', '123')
      expect(result).toBe(false)
    })

    it('returns false for empty password', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true for any username when password length >= 4', () => {
      const result = service.authenticate('unknownUser', 'longpassword')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path', () => {
      const db = (global as any).database
      service.deleteUser('123')
      expect(db.delete).toHaveBeenCalledTimes(1)
      expect(db.delete).toHaveBeenCalledWith('users/123')
    })

    it('returns undefined (void) on success', () => {
      const result = service.deleteUser('10')
      expect(result).toBeUndefined()
    })

    it('propagates errors thrown by database.delete', () => {
      const db = (global as any).database
      ;(db.delete as jest.Mock).mockImplementation(() => {
        throw new Error('DB error')
      })
      expect(() => service.deleteUser('1')).toThrow('DB error')
    })

    it('uses the provided userId verbatim in the path', () => {
      const db = (global as any).database
      service.deleteUser('a/b')
      expect(db.delete).toHaveBeenCalledWith('users/a/b')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is string "admin"', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when role is uppercase "ADMIN"', () => {
      expect(service.isAdmin({ role: 'ADMIN' })).toBe(false)
    })

    it('returns false when role is missing', () => {
      expect(service.isAdmin({})).toBe(false)
    })

    it('returns true when role is a String object containing "admin" due to loose equality', () => {
      // eslint-disable-next-line no-new-wrappers
      const role = new String('admin')
      expect(service.isAdmin({ role })).toBe(true)
    })

    it('returns true when role is an object that coerces to "admin"', () => {
      const role = { toString: () => 'admin' }
      expect(service.isAdmin({ role })).toBe(true)
    })

    it('returns false for non-matching values (numbers, booleans, different strings)', () => {
      expect(service.isAdmin({ role: true })).toBe(false)
      expect(service.isAdmin({ role: 1 })).toBe(false)
      expect(service.isAdmin({ role: 'admin ' })).toBe(false)
      expect(service.isAdmin({ role: 'user' })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      const jwt = (global as any).jwt
      ;(jwt.decode as jest.Mock).mockReturnValue({ sub: '1' })
      const result = service.validateToken('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const jwt = (global as any).jwt
      ;(jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('badtoken')
      expect(result).toBe(false)
    })

    it('passes the token through to jwt.decode unchanged', () => {
      const jwt = (global as any).jwt
      ;(jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'Bearer something.or.other'
      service.validateToken(token)
      expect(jwt.decode).toHaveBeenCalledWith(token)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const jwt = (global as any).jwt
      ;(jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => service.validateToken('token')).toThrow('decode failed')
    })

    it('returns true even if decoded token contains expired "exp" (no expiration validation)', () => {
      const jwt = (global as any).jwt
      ;(jwt.decode as jest.Mock).mockReturnValue({ exp: 1 })
      const result = service.validateToken('expired_token')
      expect(result).toBe(true)
    })
  })
})