import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let originalDatabase: any
  let originalJwt: any

  beforeEach(() => {
    originalDatabase = (global as any).database
    originalJwt = (global as any).jwt
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn() }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    ;(global as any).database = originalDatabase
    ;(global as any).jwt = originalJwt
  })

  describe('authenticate', () => {
    it('returns false when password length is 0', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4 and ignores username', () => {
      const result = service.authenticate('admin', 'verylongpassword')
      expect(result).toBe(true)
    })

    it('returns consistent result across repeated calls for the same short password', () => {
      const passwords = ['a', 'ab', 'abc']
      passwords.forEach(pw => {
        const r1 = service.authenticate('user', pw)
        const r2 = service.authenticate('other', pw)
        const r3 = service.authenticate('', pw)
        expect(r1).toBe(false)
        expect(r2).toBe(false)
        expect(r3).toBe(false)
      })
    })

    it('throws when password is undefined (non-string)', () => {
      expect(() => service.authenticate('user', undefined as any)).toThrow(TypeError)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path for a normal id', () => {
      service.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('calls database.delete with trailing slash for empty id', () => {
      service.deleteUser('')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/')
    })

    it('calls database.delete with id containing slashes without sanitization', () => {
      service.deleteUser('a/b')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/a/b')
    })

    it('propagates errors thrown by database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw new Error('db failure')
      })
      expect(() => service.deleteUser('any')).toThrow('db failure')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns true when role is new String("admin") due to loose equality', () => {
      const result = service.isAdmin({ role: new String('admin') as any })
      expect(result).toBe(true)
    })

    it('returns true when role is an object that coerces to "admin"', () => {
      const roleLike = { toString: () => 'admin' }
      const result = service.isAdmin({ role: roleLike as any })
      expect(result).toBe(true)
    })

    it('returns false when role is "ADMIN" (case-sensitive)', () => {
      const result = service.isAdmin({ role: 'ADMIN' })
      expect(result).toBe(false)
    })

    it('returns false when role is missing', () => {
      const result = service.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when role is a non-string value that does not coerce to "admin"', () => {
      const result = service.isAdmin({ role: 0 })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a payload object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '1' })
      const result = service.validateToken('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('token-null')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns undefined due to !== null check', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(undefined)
      const result = service.validateToken('token-undefined')
      expect(result).toBe(true)
    })

    it('propagates errors if jwt.decode throws', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => service.validateToken('bad-token')).toThrow('decode failed')
    })

    it('calls jwt.decode exactly once with the provided token', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'abc.def.ghi'
      const result = service.validateToken(token)
      expect(result).toBe(true)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })
  })
})