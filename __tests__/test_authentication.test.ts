import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let mockJwtDecode: jest.Mock
  let mockDbDelete: jest.Mock

  beforeEach(() => {
    mockJwtDecode = jest.fn()
    mockDbDelete = jest.fn()
    ;(global as any).jwt = { decode: mockJwtDecode }
    ;(global as any).database = { delete: mockDbDelete }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false for empty password', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false for password shorter than 4 characters', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true for password of exactly 4 characters', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for long passwords', () => {
      const longPassword = 'a'.repeat(100)
      const result = service.authenticate('user', longPassword)
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result1 = service.authenticate('alice', 'abcd')
      const result2 = service.authenticate('bob', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct path', () => {
      service.deleteUser('123')
      expect(mockDbDelete).toHaveBeenCalledTimes(1)
      expect(mockDbDelete).toHaveBeenCalledWith('users/123')
    })

    it('propagates errors thrown by database.delete', () => {
      const err = new Error('db failure')
      mockDbDelete.mockImplementation(() => {
        throw err
      })
      expect(() => service.deleteUser('u1')).toThrow(err)
      expect(mockDbDelete).toHaveBeenCalledWith('users/u1')
    })

    it('does not perform authorization checks, always attempts delete', () => {
      service.deleteUser('target-user')
      expect(mockDbDelete).toHaveBeenCalledWith('users/target-user')
    })

    it('supports multiple delete calls independently', () => {
      service.deleteUser('u1')
      service.deleteUser('u2')
      expect(mockDbDelete).toHaveBeenNthCalledWith(1, 'users/u1')
      expect(mockDbDelete).toHaveBeenNthCalledWith(2, 'users/u2')
      expect(mockDbDelete).toHaveBeenCalledTimes(2)
    })
  })

  describe('isAdmin', () => {
    it('returns true for role "admin"', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false for non-admin roles', () => {
      expect(service.isAdmin({ role: 'user' })).toBe(false)
    })

    it('uses loose equality: matches String object wrapping "admin"', () => {
      // @ts-ignore - testing runtime behavior with String object
      const strObj = new String('admin')
      expect(service.isAdmin({ role: strObj })).toBe(true)
    })

    it('uses loose equality: matches object coercible to "admin" via valueOf', () => {
      const roleObj = {
        valueOf() {
          return 'admin'
        },
        toString() {
          return 'not-admin'
        }
      }
      expect(service.isAdmin({ role: roleObj as any })).toBe(true)
    })

    it('returns false when role is undefined', () => {
      expect(service.isAdmin({})).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a payload object', () => {
      mockJwtDecode.mockReturnValue({ sub: 'u1' })
      const result = service.validateToken('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = service.validateToken('token-null')
      expect(result).toBe(false)
    })

    it('passes the token to jwt.decode', () => {
      mockJwtDecode.mockReturnValue({ foo: 'bar' })
      const token = 'abc.def.ghi'
      service.validateToken(token)
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith(token)
    })

    it('propagates error if jwt.decode throws', () => {
      const err = new Error('bad token')
      mockJwtDecode.mockImplementation(() => {
        throw err
      })
      expect(() => service.validateToken('boom')).toThrow(err)
    })
  })
})