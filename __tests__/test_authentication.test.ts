import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService - authentication and authorization behavior', () => {
  let service: UserService
  const originalDatabase = (global as any).database
  const originalJwt = (global as any).jwt

  beforeEach(() => {
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn() }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    if (originalDatabase === undefined) {
      delete (global as any).database
    } else {
      ;(global as any).database = originalDatabase
    }
    if (originalJwt === undefined) {
      delete (global as any).jwt
    } else {
      ;(global as any).jwt = originalJwt
    }
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4 (empty)', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4 (length 3)', () => {
      const result = service.authenticate('user', '123')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true for long passwords and ignores username', () => {
      const result = service.authenticate('ignored-username', 'averylongpassword')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const db = (global as any).database
      service.deleteUser('abc')
      expect(db.delete).toHaveBeenCalledTimes(1)
      expect(db.delete).toHaveBeenCalledWith('users/abc')
    })

    it('passes through provided userId even if it contains special chars or traversal-like strings', () => {
      const db = (global as any).database
      const userId = '../weird/..//id'
      service.deleteUser(userId)
      expect(db.delete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('throws ReferenceError if global database is not defined', () => {
      delete (global as any).database
      expect(() => service.deleteUser('abc')).toThrow(ReferenceError)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is the string "admin"', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      expect(service.isAdmin({ role: 'user' })).toBe(false)
      expect(service.isAdmin({ role: '' })).toBe(false)
      expect(service.isAdmin({ role: 'Admin' })).toBe(false)
    })

    it('uses loose equality: returns true for new String("admin")', () => {
      // @ts-expect-error intentional any
      const roleObj: any = new String('admin')
      expect(service.isAdmin({ role: roleObj })).toBe(true)
    })

    it('uses loose equality: returns true for ["admin"] due to coercion', () => {
      // @ts-expect-error intentional any
      expect(service.isAdmin({ role: ['admin'] as any })).toBe(true)
    })

    it('throws TypeError if user is null or undefined when accessing role', () => {
      // @ts-expect-error testing runtime behavior with invalid input
      expect(() => service.isAdmin(null)).toThrow()
      // @ts-expect-error testing runtime behavior with invalid input
      expect(() => service.isAdmin(undefined)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      const jwt = (global as any).jwt
      jwt.decode.mockReturnValue({ sub: '123' })
      const result = service.validateToken('token')
      expect(jwt.decode).toHaveBeenCalledWith('token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const jwt = (global as any).jwt
      jwt.decode.mockReturnValue(null)
      const result = service.validateToken('token')
      expect(result).toBe(false)
    })

    it('returns true even if jwt.decode returns undefined (decoded !== null)', () => {
      const jwt = (global as any).jwt
      jwt.decode.mockReturnValue(undefined)
      const result = service.validateToken('token')
      expect(result).toBe(true)
    })

    it('throws ReferenceError if jwt is not defined', () => {
      delete (global as any).jwt
      expect(() => service.validateToken('token')).toThrow(ReferenceError)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const jwt = (global as any).jwt
      jwt.decode.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('token')).toThrow('decode error')
    })
  })
})