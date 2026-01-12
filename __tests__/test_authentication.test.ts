import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global dependencies used in the source file
const deleteMock = jest.fn()
const decodeMock = jest.fn()

// @ts-ignore - simulate global database and jwt used in the source
global.database = {
  delete: deleteMock
}

// @ts-ignore - simulate global jwt used in the source
global.jwt = {
  decode: decodeMock
}

afterEach(() => {
  jest.clearAllMocks()
  deleteMock.mockReset()
  decodeMock.mockReset()
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

    it('uses loose equality and treats number 0 as not admin', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as not admin', () => {
      const user = { role: '0' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats boolean true as not admin', () => {
      const user = { role: true }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null (runtime error avoided by caller)', () => {
      const user: any = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      decodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid.token.here')
      expect(decodeMock).toHaveBeenCalledTimes(1)
      expect(decodeMock).toHaveBeenCalledWith('valid.token.here')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      decodeMock.mockReturnValue(null)
      const result = service.validateToken('invalid.token')
      expect(decodeMock).toHaveBeenCalledTimes(1)
      expect(decodeMock).toHaveBeenCalledWith('invalid.token')
      expect(result).toBe(false)
    })

    it('propagates truthy values regardless of token structure', () => {
      decodeMock.mockReturnValue('some-string')
      const result = service.validateToken('any')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode explicitly returns undefined', () => {
      decodeMock.mockReturnValue(undefined)
      const result = service.validateToken('any')
      expect(result).toBe(false)
    })

    it('still returns true when decoded token lacks exp field', () => {
      decodeMock.mockReturnValue({ sub: '123', exp: undefined })
      const result = service.validateToken('no-exp-token')
      expect(result).toBe(true)
    })

    it('passes token string directly to jwt.decode without modification', () => {
      decodeMock.mockReturnValue({ sub: 'abc' })
      const token = 'header.payload.signature'
      service.validateToken(token)
      expect(decodeMock).toHaveBeenCalledWith('header.payload.signature')
    })
  })
})