import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global dependencies used in the source file
const deleteMock = jest.fn()
const jwtDecodeMock = jest.fn()

// @ts-ignore - simulate global database object
global.database = {
  delete: deleteMock
}

// @ts-ignore - simulate global jwt object
global.jwt = {
  decode: jwtDecodeMock
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
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
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith('users/123')
    })

    it('passes userId directly into path without validation', () => {
      const userId = '../admin'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/../admin')
    })

    it('allows empty userId and still calls database.delete', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/')
    })

    it('allows special characters in userId', () => {
      const userId = 'user:!@#$%^&*()'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/user:!@#$%^&*()')
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

    it('uses loose equality and treats String object with value "admin" as admin', () => {
      const user = { role: new String('admin') as unknown as string }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('treats numeric 0 as not admin', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('treats null role as not admin', () => {
      const user = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user object has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      jwtDecodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid.token.here')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('valid.token.here')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('invalid.token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('invalid.token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns an empty object', () => {
      jwtDecodeMock.mockReturnValue({})
      const result = service.validateToken('empty.payload.token')
      expect(result).toBe(true)
    })

    it('propagates any value from jwt.decode and only checks for null', () => {
      jwtDecodeMock.mockReturnValue(0 as any)
      const result = service.validateToken('zero.payload.token')
      expect(result).toBe(true)
    })

    it('treats undefined from jwt.decode as invalid token', () => {
      jwtDecodeMock.mockReturnValue(undefined)
      const result = service.validateToken('undefined.payload.token')
      expect(result).toBe(false)
    })

    it('still calls jwt.decode even with empty token string', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('')
      expect(jwtDecodeMock).toHaveBeenCalledWith('')
      expect(result).toBe(false)
    })
  })
})