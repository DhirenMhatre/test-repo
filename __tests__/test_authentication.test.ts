import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', 'abc')
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

    it('returns true when password length is greater than or equal to 4 regardless of username', () => {
      const result1 = service.authenticate('anyuser', 'abcd')
      const result2 = service.authenticate('admin', 'abcdef')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path when global database exists', () => {
      const del = jest.fn()
      ;(global as any).database = { delete: del }
      service.deleteUser('123')
      expect(del).toHaveBeenCalledTimes(1)
      expect(del).toHaveBeenCalledWith('users/123')
    })

    it('propagates error thrown by database.delete', () => {
      const del = jest.fn(() => {
        throw new Error('db fail')
      })
      ;(global as any).database = { delete: del }
      expect(() => service.deleteUser('999')).toThrow('db fail')
      expect(del).toHaveBeenCalledWith('users/999')
    })

    it('throws ReferenceError when global database is not defined', () => {
      expect(() => service.deleteUser('no-db')).toThrow(ReferenceError)
    })
  })

  describe('isAdmin', () => {
    it('returns true for user with role "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('is case-sensitive: returns false for "Admin"', () => {
      const result = service.isAdmin({ role: 'Admin' })
      expect(result).toBe(false)
    })

    it('coerces String object due to == and returns true', () => {
      const roleObj = new (String as any)('admin')
      const result = service.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns false when role is missing or undefined', () => {
      const result1 = service.isAdmin({})
      const result2 = service.isAdmin({ role: undefined })
      expect(result1).toBe(false)
      expect(result2).toBe(false)
    })

    it('returns false for role "admin " with trailing space', () => {
      const result = service.isAdmin({ role: 'admin ' })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object (any payload)', () => {
      const decode = jest.fn(() => ({ sub: 'u1' }))
      ;(global as any).jwt = { decode }
      const result = service.validateToken('token-abc')
      expect(decode).toHaveBeenCalledWith('token-abc')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const decode = jest.fn(() => null)
      ;(global as any).jwt = { decode }
      const result = service.validateToken('invalid-token')
      expect(decode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('throws ReferenceError when jwt is not defined', () => {
      expect(() => service.validateToken('any')).toThrow(ReferenceError)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const decode = jest.fn(() => {
        throw new Error('decode fail')
      })
      ;(global as any).jwt = { decode }
      expect(() => service.validateToken('boom')).toThrow('decode fail')
      expect(decode).toHaveBeenCalledWith('boom')
    })

    it('returns true even if decoded token appears expired (no exp check)', () => {
      const decode = jest.fn(() => ({ exp: 1 }))
      ;(global as any).jwt = { decode }
      const result = service.validateToken('expired-like')
      expect(result).toBe(true)
    })
  })
})