import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: jest.fn()
}))

const jwt = require('jwt')

describe('UserService', () => {
  let userService: UserService
  let originalDatabase: any

  beforeEach(() => {
    userService = new UserService()

    originalDatabase = (global as any).database
    ;(global as any).database = {
      delete: jest.fn()
    }

    jest.clearAllMocks()
  })

  afterEach(() => {
    ;(global as any).database = originalDatabase
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns true for password length equal to 4', () => {
      const result = userService.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true for password length greater than 4', () => {
      const result = userService.authenticate('user', '12345')
      expect(result).toBe(true)
    })

    it('returns false for password length less than 4 (length 0)', () => {
      const result = userService.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false for password length less than 4 (length 1)', () => {
      const result = userService.authenticate('user', 'a')
      expect(result).toBe(false)
    })

    it('returns false for password length less than 4 (length 3)', () => {
      const result = userService.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('does not check username at all', () => {
      const result1 = userService.authenticate('user1', '1234')
      const result2 = userService.authenticate('user2', '1234')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct user path', () => {
      userService.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('allows deletion of any user id string', () => {
      userService.deleteUser('some-random-id')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/some-random-id')
    })

    it('passes through special characters in userId to database path', () => {
      userService.deleteUser('../admin')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/../admin')
    })

    it('does not perform any authorization checks before deleting', () => {
      userService.deleteUser('no-auth-check')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const result = userService.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      const result = userService.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('uses loose equality and treats number 0 as non-admin', () => {
      const result = userService.isAdmin({ role: 0 })
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as non-admin', () => {
      const result = userService.isAdmin({ role: '0' })
      expect(result).toBe(false)
    })

    it('uses loose equality and treats boolean true as non-admin', () => {
      const result = userService.isAdmin({ role: true })
      expect(result).toBe(false)
    })

    it('returns false when role is undefined', () => {
      const result = userService.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when user object is null', () => {
      const result = userService.isAdmin(null as any)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
      const result = userService.validateToken('token-123')
      expect(jwt.decode).toHaveBeenCalledWith('token-123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue(null)
      const result = userService.validateToken('invalid-token')
      expect(jwt.decode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('propagates exceptions thrown by jwt.decode', () => {
      ;(jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => userService.validateToken('bad-token')).toThrow('decode error')
      expect(jwt.decode).toHaveBeenCalledWith('bad-token')
    })

    it('treats any truthy decoded value as valid', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue('some-string')
      const result = userService.validateToken('token-string')
      expect(result).toBe(true)
    })

    it('treats decoded empty object as valid', () => {
      ;(jwt.decode as jest.Mock).mockReturnValue({})
      const result = userService.validateToken('empty-payload')
      expect(result).toBe(true)
    })
  })
})