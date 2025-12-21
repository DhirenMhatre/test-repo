import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let mockDbDelete: jest.Mock
  let mockJwtDecode: jest.Mock

  beforeEach(() => {
    mockDbDelete = jest.fn()
    mockJwtDecode = jest.fn()
    ;(global as any).database = { delete: mockDbDelete }
    ;(global as any).jwt = { decode: mockJwtDecode }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false for password length < 4 (empty password)', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false for password length 1', () => {
      const result = service.authenticate('user', 'a')
      expect(result).toBe(false)
    })

    it('returns false for password length 3', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true for password length exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for long password', () => {
      const result = service.authenticate('user', 'averylongpassword')
      expect(result).toBe(true)
    })

    it('ignores username and checks only password length', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
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

    it('returns undefined (void) after calling delete', () => {
      const res = service.deleteUser('xyz')
      expect(res).toBeUndefined()
      expect(mockDbDelete).toHaveBeenCalledWith('users/xyz')
    })

    it('propagates error thrown by database.delete', () => {
      mockDbDelete.mockImplementation(() => { throw new Error('db error') })
      expect(() => service.deleteUser('u-err')).toThrow('db error')
    })

    it('constructs path without encoding or sanitizing userId', () => {
      service.deleteUser('abc/123')
      expect(mockDbDelete).toHaveBeenCalledWith('users/abc/123')
    })

    it('works with empty userId resulting in "users/" path', () => {
      service.deleteUser('')
      expect(mockDbDelete).toHaveBeenCalledWith('users/')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when user.role is "Admin" (case-sensitive)', () => {
      expect(service.isAdmin({ role: 'Admin' })).toBe(false)
    })

    it('uses loose equality: matches when role is a String object "admin"', () => {
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin')
      expect(service.isAdmin({ role: roleObj })).toBe(true)
    })

    it('uses loose equality: coerces object role whose valueOf returns "admin"', () => {
      const roleObj = { valueOf: () => 'admin' }
      expect(service.isAdmin({ role: roleObj })).toBe(true)
    })

    it('returns false when role is missing/undefined', () => {
      expect(service.isAdmin({})).toBe(false)
      expect(service.isAdmin({ role: undefined })).toBe(false)
    })

    it('returns false when role is not "admin"', () => {
      expect(service.isAdmin({ role: 'user' })).toBe(false)
      expect(service.isAdmin({ role: 1 })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      mockJwtDecode.mockReturnValue({ sub: 'u1' })
      const ok = service.validateToken('token123')
      expect(ok).toBe(true)
      expect(mockJwtDecode).toHaveBeenCalledWith('token123')
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const ok = service.validateToken('badtoken')
      expect(ok).toBe(false)
      expect(mockJwtDecode).toHaveBeenCalledWith('badtoken')
    })

    it('returns true when jwt.decode returns undefined (because !== null)', () => {
      mockJwtDecode.mockReturnValue(undefined)
      const ok = service.validateToken('weirdtoken')
      expect(ok).toBe(true)
      expect(mockJwtDecode).toHaveBeenCalledWith('weirdtoken')
    })

    it('propagates error thrown by jwt.decode', () => {
      mockJwtDecode.mockImplementation(() => { throw new Error('decode error') })
      expect(() => service.validateToken('crashtoken')).toThrow('decode error')
    })
  })
})