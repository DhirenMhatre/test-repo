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

    it('does not check username value and only relies on password length', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('anotherUser', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('treats empty password as invalid', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith('users/123')
    })

    it('passes userId directly into the path without validation', () => {
      const userId = '../admin'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/../admin')
    })

    it('allows deletion with empty userId string', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/')
    })

    it('allows deletion with special characters in userId', () => {
      const userId = 'user:!@#'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/user:!@#')
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

    it('uses loose equality and treats role number 1 as not equal to "admin"', () => {
      const user = { role: 1 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null or undefined-like object', () => {
      const user: any = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('treats string "admin " with trailing space as not admin', () => {
      const user = { role: 'admin ' }
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

    it('propagates any value from jwt.decode and only checks for null', () => {
      jwtDecodeMock.mockReturnValue(false)
      const result = service.validateToken('token')
      expect(result).toBe(true)
    })

    it('treats empty string token as valid if jwt.decode does not return null', () => {
      jwtDecodeMock.mockReturnValue({})
      const result = service.validateToken('')
      expect(jwtDecodeMock).toHaveBeenCalledWith('')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode explicitly returns null for empty token', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('')
      expect(result).toBe(false)
    })
  })

  describe('integration of methods behavior', () => {
    it('allows authenticate to succeed and then deleteUser to be called without any authorization check', () => {
      const authResult = service.authenticate('user', 'abcd')
      expect(authResult).toBe(true)

      const userId = '456'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/456')
    })

    it('does not prevent deleteUser from being called even if authenticate fails', () => {
      const authResult = service.authenticate('user', '123')
      expect(authResult).toBe(false)

      const userId = '789'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/789')
    })
  })
})