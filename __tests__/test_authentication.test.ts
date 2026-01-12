import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: jest.fn()
}))

jest.mock('database', () => ({
  ...jest.requireActual('database'),
  delete: jest.fn()
}))

import jwt from 'jwt'
import database from 'database'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
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

    it('treats any string of length >= 4 as valid even if it looks weak', () => {
      const result = service.authenticate('user', '0000')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(database.delete).toHaveBeenCalledTimes(1)
      expect(database.delete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('allows deletion for any userId string', () => {
      const userId = 'any-user-id'
      service.deleteUser(userId)
      expect(database.delete).toHaveBeenCalledWith('users/any-user-id')
    })

    it('passes through special characters in userId to database.delete', () => {
      const userId = 'user/with/slash'
      service.deleteUser(userId)
      expect(database.delete).toHaveBeenCalledWith('users/user/with/slash')
    })

    it('does not perform any checks before calling database.delete', () => {
      const userId = 'no-checks'
      service.deleteUser(userId)
      expect(database.delete).toHaveBeenCalledTimes(1)
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

    it('uses loose equality and treats number 0 as equal to string "0"', () => {
      const user = { role: 0 as any }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats String object "admin" as admin', () => {
      const user = { role: new String('admin') as any }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when user has no role property', () => {
      const user = {} as any
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null or undefined-like object', () => {
      const user = { role: null } as any
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
      const result = service.validateToken('token')
      expect(jwt.decode).toHaveBeenCalledTimes(1)
      expect(jwt.decode).toHaveBeenCalledWith('token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(jwt.decode).toHaveBeenCalledTimes(1)
      expect(jwt.decode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('treats any non-null decoded value as valid, including empty object', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({})
      const result = service.validateToken('any-token')
      expect(result).toBe(true)
    })

    it('propagates exceptions thrown by jwt.decode', () => {
      ;(jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('bad-token')).toThrow('decode error')
    })

    it('does not perform any expiration or claim checks on decoded token', () => {
      const decoded = { exp: 0, sub: 'user' }
      ;(jwt.decode as jest.Mock).mockReturnValue(decoded)
      const result = service.validateToken('expired-token')
      expect(result).toBe(true)
    })
  })
})