import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global dependencies used in the source file
const deleteMock = jest.fn()
const jwtDecodeMock = jest.fn()

// @ts-ignore - simulate global database and jwt used in the source
global.database = {
  delete: deleteMock
}

// @ts-ignore - simulate global jwt used in the source
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

    it('does not check username at all', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('treats empty password as invalid due to length check', () => {
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

    it('allows empty userId and still calls database.delete', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/')
    })

    it('does not perform any authorization checks before deleting', () => {
      const userId = 'no-auth-check'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledTimes(1)
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

    it('uses loose equality and treats number 0 as not equal to "admin"', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as not equal to "admin"', () => {
      const user = { role: '0' }
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
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      jwtDecodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid-token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('valid-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('propagates truthy values from jwt.decode regardless of content', () => {
      jwtDecodeMock.mockReturnValue('some-string')
      const result = service.validateToken('token')
      expect(result).toBe(true)
    })

    it('treats undefined from jwt.decode as falsy and returns false', () => {
      jwtDecodeMock.mockReturnValue(undefined)
      const result = service.validateToken('token')
      expect(result).toBe(false)
    })

    it('does not perform any expiration or claim validation beyond non-null check', () => {
      const decodedPayload = { exp: 0, sub: 'user', anyField: 'value' }
      jwtDecodeMock.mockReturnValue(decodedPayload)
      const result = service.validateToken('expired-token')
      expect(result).toBe(true)
      expect(jwtDecodeMock).toHaveBeenCalledWith('expired-token')
    })
  })

  describe('integration of methods behavior', () => {
    it('allows authenticate to succeed even with known hardcoded admin password', () => {
      const result = service.authenticate('admin', 'admin123')
      expect(result).toBe(true)
    })

    it('authenticate does not check against hardcoded API key', () => {
      const result = service.authenticate('any', 'sk_live_abc123xyz')
      expect(result).toBe(true)
    })

    it('combines isAdmin and deleteUser without any internal linkage or checks', () => {
      const user = { role: 'user' }
      const isAdminResult = service.isAdmin(user)
      service.deleteUser('123')
      expect(isAdminResult).toBe(false)
      expect(deleteMock).toHaveBeenCalledWith('users/123')
    })
  })
})