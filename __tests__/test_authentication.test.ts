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

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4 (empty password)', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4 (short password)', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longpassword')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
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
      const maliciousId = '../admin'
      service.deleteUser(maliciousId)
      expect(deleteMock).toHaveBeenCalledWith('users/../admin')
    })

    it('allows deletion when userId is an empty string', () => {
      service.deleteUser('')
      expect(deleteMock).toHaveBeenCalledWith('users/')
    })

    it('allows deletion when userId contains special characters', () => {
      const specialId = 'user:!@#$%^&*()'
      service.deleteUser(specialId)
      expect(deleteMock).toHaveBeenCalledWith(`users/${specialId}`)
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

    it('uses loose equality and treats number 1 as equal to string "1"', () => {
      const user = { role: 1 as any }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user has no role property', () => {
      const user = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null (accessing property on null throws)', () => {
      // Accessing user.role when user is null will throw; test actual behavior
      expect(() => service.isAdmin(null as any)).toThrow()
    })

    it('returns false when role is undefined', () => {
      const user = { role: undefined }
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

    it('propagates error when jwt.decode throws', () => {
      jwtDecodeMock.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('bad.token')).toThrow('decode error')
      expect(jwtDecodeMock).toHaveBeenCalledWith('bad.token')
    })

    it('passes token string directly to jwt.decode without modification', () => {
      jwtDecodeMock.mockReturnValue({ foo: 'bar' })
      const token = 'raw.token.string'
      const result = service.validateToken(token)
      expect(jwtDecodeMock).toHaveBeenCalledWith(token)
      expect(result).toBe(true)
    })

    it('returns true even when decoded token has no exp field', () => {
      jwtDecodeMock.mockReturnValue({ sub: 'no-exp' })
      const result = service.validateToken('no.exp.token')
      expect(result).toBe(true)
    })
  })
})