import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  return {
    ...actual
  }
})

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
      const result = service.authenticate('user', '12345')
      expect(result).toBe(true)
    })

    it('does not check username value at all', () => {
      const result1 = service.authenticate('anyUser', 'abcd')
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
    it('calls database.delete with correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('allows deletion for any userId string', () => {
      const userId = 'some-random-id'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('passes through special characters in userId to database.delete', () => {
      const userId = '../admin'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('does not perform any validation or authorization checks before delete', () => {
      const userId = 'no-checks'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledTimes(1)
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is string "admin"', () => {
      const user = { role: 'admin' }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const user = { role: 'user' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality so number 0 compared to "admin" is false', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null (accessing role yields undefined)', () => {
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

    it('propagates any value from jwt.decode as long as it is not null', () => {
      jwtDecodeMock.mockReturnValue(false)
      const result = service.validateToken('token-with-false-payload')
      expect(result).toBe(true)
    })

    it('treats undefined from jwt.decode as non-null and returns true', () => {
      jwtDecodeMock.mockReturnValue(undefined)
      const result = service.validateToken('token-with-undefined')
      expect(result).toBe(true)
    })

    it('calls jwt.decode exactly once per validateToken invocation', () => {
      jwtDecodeMock.mockReturnValue({ some: 'payload' })
      service.validateToken('t1')
      service.validateToken('t2')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(2)
      expect(jwtDecodeMock).toHaveBeenNthCalledWith(1, 't1')
      expect(jwtDecodeMock).toHaveBeenNthCalledWith(2, 't2')
    })
  })
})