import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService
  let mockDbDelete: jest.Mock
  let mockJwtDecode: jest.Mock

  beforeEach(() => {
    mockDbDelete = jest.fn()
    mockJwtDecode = jest.fn().mockReturnValue({ sub: 'u1' })
    ;(global as any).database = { delete: mockDbDelete }
    ;(global as any).jwt = { decode: mockJwtDecode }
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false for empty password', () => {
      const result = svc.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false for short password length 3', () => {
      const result = svc.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true for password length exactly 4', () => {
      const result = svc.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for longer passwords', () => {
      const result = svc.authenticate('user', 'averylongpassword')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const valid = svc.authenticate('admin', 'pass')
      const invalid = svc.authenticate('not_admin', '123')
      expect(valid).toBe(true)
      expect(invalid).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct user path', () => {
      svc.deleteUser('123')
      expect(mockDbDelete).toHaveBeenCalledTimes(1)
      expect(mockDbDelete).toHaveBeenCalledWith('users/123')
    })

    it('calls database.delete with "users/" when userId is empty string', () => {
      svc.deleteUser('')
      expect(mockDbDelete).toHaveBeenCalledTimes(1)
      expect(mockDbDelete).toHaveBeenCalledWith('users/')
    })

    it('propagates errors thrown by database.delete', () => {
      mockDbDelete.mockImplementation(() => {
        throw new Error('DB error')
      })
      expect(() => svc.deleteUser('fail')).toThrow('DB error')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly string "admin"', () => {
      const result = svc.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns true when role is a String object "admin" due to == coercion', () => {
      const result = svc.isAdmin({ role: new String('admin') as unknown as string })
      expect(result).toBe(true)
    })

    it('returns true when role object toString returns "admin" due to == coercion', () => {
      const roleObj = { toString: () => 'admin' }
      const result = svc.isAdmin({ role: roleObj as unknown as string })
      expect(result).toBe(true)
    })

    it('returns false for different case "Admin"', () => {
      const result = svc.isAdmin({ role: 'Admin' })
      expect(result).toBe(false)
    })

    it('returns false when role is "user"', () => {
      const result = svc.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('throws when user is undefined', () => {
      expect(() => svc.isAdmin(undefined as any)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      mockJwtDecode.mockReturnValue({ foo: 'bar' })
      const result = svc.validateToken('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = svc.validateToken('invalid')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns undefined due to !== null check', () => {
      mockJwtDecode.mockReturnValue(undefined)
      const result = svc.validateToken('maybe')
      expect(result).toBe(true)
    })

    it('passes the token argument to jwt.decode', () => {
      const token = 'abc.def.ghi'
      svc.validateToken(token)
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith(token)
    })

    it('propagates errors from jwt.decode', () => {
      mockJwtDecode.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => svc.validateToken('boom')).toThrow('decode error')
    })
  })
})