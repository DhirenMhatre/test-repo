import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global-like dependencies used inside the module
const deleteMock = jest.fn()
const decodeMock = jest.fn()

// @ts-ignore - simulate global database and jwt used by the source file
global.database = {
  delete: deleteMock
}

// @ts-ignore - simulate global jwt used by the source file
global.jwt = {
  decode: decodeMock
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

    it('treats empty string as invalid password', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct user path', () => {
      service.deleteUser('123')
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith('users/123')
    })

    it('allows deleting arbitrary user id without authorization checks', () => {
      service.deleteUser('any-user-id')
      expect(deleteMock).toHaveBeenCalledWith('users/any-user-id')
    })

    it('passes exactly the provided userId into the path', () => {
      const userId = 'user/with/slash'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('does not return any value', () => {
      const result = service.deleteUser('no-return')
      expect(result).toBeUndefined()
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role == "admin" (string)', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const result = service.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('uses loose equality so number 0 is not equal to "admin"', () => {
      const result = service.isAdmin({ role: 0 })
      expect(result).toBe(false)
    })

    it('returns false when user.role is undefined', () => {
      const result = service.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when user is null', () => {
      const result = service.isAdmin(null as any)
      expect(result).toBe(false)
    })

    it('returns false when user is undefined', () => {
      const result = service.isAdmin(undefined as any)
      expect(result).toBe(false)
    })

    it('treats "ADMIN" (uppercase) as non-admin because of case sensitivity', () => {
      const result = service.isAdmin({ role: 'ADMIN' })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      decodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid-token')
      expect(decodeMock).toHaveBeenCalledTimes(1)
      expect(decodeMock).toHaveBeenCalledWith('valid-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      decodeMock.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(decodeMock).toHaveBeenCalledTimes(1)
      expect(decodeMock).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('propagates any error thrown by jwt.decode', () => {
      const error = new Error('decode failed')
      decodeMock.mockImplementation(() => {
        throw error
      })
      expect(() => service.validateToken('bad-token')).toThrow(error)
      expect(decodeMock).toHaveBeenCalledWith('bad-token')
    })

    it('treats any non-null decoded value as valid, including empty object', () => {
      decodeMock.mockReturnValue({})
      const result = service.validateToken('token-with-empty-payload')
      expect(result).toBe(true)
    })

    it('treats non-object decoded values (like string) as valid as long as not null', () => {
      decodeMock.mockReturnValue('payload-string')
      const result = service.validateToken('string-payload-token')
      expect(result).toBe(true)
    })
  })
})