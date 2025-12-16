import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let mockDatabaseDelete: jest.Mock
  let mockJwtDecode: jest.Mock

  beforeEach(() => {
    mockDatabaseDelete = jest.fn()
    mockJwtDecode = jest.fn()
    ;(global as any).database = { delete: mockDatabaseDelete }
    ;(global as any).jwt = { decode: mockJwtDecode }
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

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for longer passwords regardless of username', () => {
      const result = service.authenticate('', 'longpassword')
      expect(result).toBe(true)
    })

    it('ignores username and only validates password length', () => {
      const result = service.authenticate('any-username', '1234')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with users/<id> path', () => {
      service.deleteUser('123')
      expect(mockDatabaseDelete).toHaveBeenCalledTimes(1)
      expect(mockDatabaseDelete).toHaveBeenCalledWith('users/123')
    })

    it('calls database.delete even for empty id (no authorization check)', () => {
      service.deleteUser('')
      expect(mockDatabaseDelete).toHaveBeenCalledWith('users/')
    })

    it('propagates errors thrown by database.delete', () => {
      mockDatabaseDelete.mockImplementation(() => {
        throw new Error('DB_FAIL')
      })
      expect(() => service.deleteUser('u1')).toThrow('DB_FAIL')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is the string "admin"', () => {
      const user = { role: 'admin' }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('uses loose equality so String object "admin" is treated as admin', () => {
      // new String('admin') is not strictly equal to 'admin' but == will coerce
      const user = { role: new String('admin') as unknown as string }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('returns false for different casing', () => {
      const user = { role: 'ADMIN' }
      expect(service.isAdmin(user)).toBe(false)
    })

    it('returns false when role is missing or undefined', () => {
      const user: any = {}
      expect(service.isAdmin(user)).toBe(false)
    })

    it('returns false for non-string roles', () => {
      const user = { role: 0 as unknown as string }
      expect(service.isAdmin(user)).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      mockJwtDecode.mockReturnValue({ sub: 'u1' })
      const result = service.validateToken('token-1')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(result).toBe(false)
    })

    it('passes the token to jwt.decode', () => {
      mockJwtDecode.mockReturnValue({})
      const token = 'some-token'
      const result = service.validateToken(token)
      expect(result).toBe(true)
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith(token)
    })

    it('propagates errors from jwt.decode', () => {
      mockJwtDecode.mockImplementation(() => {
        throw new Error('DECODE_ERROR')
      })
      expect(() => service.validateToken('t')).toThrow('DECODE_ERROR')
    })

    it('does not validate expiration and returns true as long as decoded is not null', () => {
      mockJwtDecode.mockReturnValue({ exp: 0 })
      const result = service.validateToken('expired-looking-token')
      expect(result).toBe(true)
    })
  })
})