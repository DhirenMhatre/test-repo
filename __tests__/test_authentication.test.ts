import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  return {
    ...actual
  }
})

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: jest.fn()
}))

const mockDelete = jest.fn()
jest.mock('database', () => ({
  ...jest.requireActual('database'),
  delete: (...args: any[]) => mockDelete(...args)
}))

import jwt from 'jwt'
import database from 'database'

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
    it('calls database.delete with correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('passes the exact string "users/<id>" to database.delete', () => {
      const userId = 'abc-xyz'
      service.deleteUser(userId)
      const callArg = mockDelete.mock.calls[0][0]
      expect(callArg).toBe('users/abc-xyz')
    })

    it('allows deletion with empty userId and still calls database.delete', () => {
      service.deleteUser('')
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith('users/')
    })

    it('allows deletion with special characters in userId', () => {
      const userId = '../etc/passwd'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith('users/../etc/passwd')
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

    it('uses loose equality and treats object without role as not admin', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats null role as not admin', () => {
      const user: any = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
      const result = service.validateToken('token123')
      expect(jwt.decode).toHaveBeenCalledTimes(1)
      expect(jwt.decode).toHaveBeenCalledWith('token123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(jwt.decode).toHaveBeenCalledTimes(1)
      expect(jwt.decode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns an empty object', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({})
      const result = service.validateToken('empty-payload-token')
      expect(result).toBe(true)
    })

    it('propagates any value from jwt.decode and only checks for non-null', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue('decoded-string')
      const result = service.validateToken('some-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns undefined (treated as null check)', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue(undefined)
      const result = service.validateToken('undefined-token')
      expect(result).toBe(false)
    })
  })
})