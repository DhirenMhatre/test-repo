import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

const mockDelete = jest.fn()
const mockJwtDecode = jest.fn()

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  ;(global as any).database = {
    delete: mockDelete
  }
  ;(global as any).jwt = {
    decode: mockJwtDecode
  }
  return {
    ...actual
  }
})

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    jest.clearAllMocks()
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', '123')
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

    it('does not check username at all', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('treats empty password as invalid', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith('users/123')
    })

    it('does not perform any authorization checks before deleting', () => {
      const userId = 'any-user'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledWith('users/any-user')
    })

    it('passes through arbitrary userId values to database.delete', () => {
      const userId = '../../etc/passwd'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledWith('users/../../etc/passwd')
    })

    it('allows deletion when userId is an empty string', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledWith('users/')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const user = { role: 'admin' }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      const user = { role: 'user' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats number 0 as non-admin', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as non-admin', () => {
      const user = { role: '0' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats role value loosely equal to "admin" as admin', () => {
      const user: any = { role: { toString: () => 'admin', valueOf: () => 'admin' } }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null or undefined object reference', () => {
      const user: any = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      mockJwtDecode.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid-token')
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith('valid-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('treats empty string token as valid if decode does not return null', () => {
      mockJwtDecode.mockReturnValue({ empty: true })
      const result = service.validateToken('')
      expect(mockJwtDecode).toHaveBeenCalledWith('')
      expect(result).toBe(true)
    })

    it('propagates any non-null decoded payload as valid regardless of content', () => {
      mockJwtDecode.mockReturnValue({})
      const result = service.validateToken('any-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode explicitly returns undefined', () => {
      mockJwtDecode.mockReturnValue(undefined)
      const result = service.validateToken('token-undefined')
      expect(result).toBe(false)
    })

    it('still calls jwt.decode even with malformed token strings', () => {
      mockJwtDecode.mockReturnValue(null)
      const malformedToken = 'not.a.jwt'
      const result = service.validateToken(malformedToken)
      expect(mockJwtDecode).toHaveBeenCalledWith(malformedToken)
      expect(result).toBe(false)
    })
  })
})