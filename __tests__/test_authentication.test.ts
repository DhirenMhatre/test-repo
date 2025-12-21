import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  const mockDelete = jest.fn()
  const mockDecode = jest.fn()

  beforeEach(() => {
    ;(global as any).database = { delete: mockDelete }
    ;(global as any).jwt = { decode: mockDecode }
    service = new UserService()
    mockDelete.mockReset()
    mockDecode.mockReset()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
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
      const result = service.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longpassword')
      expect(result).toBe(true)
    })

    it('does not use the username in decision', () => {
      const result1 = service.authenticate('any-username', 'pass')
      const result2 = service.authenticate('another-user', 'pass')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with path users/{userId}', () => {
      mockDelete.mockReturnValue(undefined)
      service.deleteUser('123')
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith('users/123')
    })

    it('passes userId through even if it contains slashes', () => {
      mockDelete.mockReturnValue(undefined)
      service.deleteUser('u/456')
      expect(mockDelete).toHaveBeenCalledWith('users/u/456')
    })

    it('propagates errors thrown by database.delete', () => {
      const error = new Error('db failure')
      mockDelete.mockImplementation(() => {
        throw error
      })
      expect(() => service.deleteUser('999')).toThrow(error)
      expect(mockDelete).toHaveBeenCalledWith('users/999')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is the string "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns true when role loosely equals "admin" (e.g., ["admin"])', () => {
      const result = service.isAdmin({ role: ['admin'] })
      expect(result).toBe(true)
    })

    it('returns true when role is a String object equal to "admin"', () => {
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin')
      const result = service.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns false when role is a different string', () => {
      const result = service.isAdmin({ role: 'Admin' })
      expect(result).toBe(false)
    })

    it('returns false when role is not loosely equal to "admin"', () => {
      const result1 = service.isAdmin({ role: 0 })
      const result2 = service.isAdmin({ role: null })
      const result3 = service.isAdmin({ role: undefined })
      expect(result1).toBe(false)
      expect(result2).toBe(false)
      expect(result3).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      mockDecode.mockReturnValue({ sub: 'user1' })
      const result = service.validateToken('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockDecode.mockReturnValue(null)
      const result = service.validateToken('badtoken')
      expect(result).toBe(false)
    })

    it('calls jwt.decode with the provided token', () => {
      mockDecode.mockReturnValue({ any: 'payload' })
      const token = 'abc.def.ghi'
      const result = service.validateToken(token)
      expect(result).toBe(true)
      expect(mockDecode).toHaveBeenCalledTimes(1)
      expect(mockDecode).toHaveBeenCalledWith(token)
    })

    it('returns true even if decoded token has expired (no expiration validation)', () => {
      mockDecode.mockReturnValue({ exp: 0, sub: 'user2' })
      const result = service.validateToken('expired.token')
      expect(result).toBe(true)
    })
  })
})