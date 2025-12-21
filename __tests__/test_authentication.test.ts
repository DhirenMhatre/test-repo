import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare const global: any

describe('UserService', () => {
  beforeEach(() => {
    global.database = { delete: jest.fn() }
    global.jwt = { decode: jest.fn() }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete global.database
    delete global.jwt
  })

  describe('authenticate', () => {
    it('returns false for empty password', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '')).toBe(false)
    })

    it('returns false for password length less than 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', 'a')).toBe(false)
      expect(svc.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true for password length 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', 'abcd')).toBe(true)
    })

    it('returns true for password length greater than or equal to 4 regardless of username', () => {
      const svc = new UserService()
      expect(svc.authenticate('anyone', 'longpassword')).toBe(true)
      expect(svc.authenticate('anotherUser', '1234')).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path for a simple user id', () => {
      const svc = new UserService()
      svc.deleteUser('u1')
      expect(global.database.delete).toHaveBeenCalledTimes(1)
      expect(global.database.delete).toHaveBeenCalledWith('users/u1')
    })

    it('calls database.delete with the correct path for a complex user id', () => {
      const svc = new UserService()
      const complexId = 'user-123_~:test.id'
      svc.deleteUser(complexId)
      expect(global.database.delete).toHaveBeenCalledWith(`users/${complexId}`)
    })

    it('propagates errors thrown by database.delete', () => {
      const svc = new UserService()
      const err = new Error('db failure')
      global.database.delete.mockImplementation(() => {
        throw err
      })
      expect(() => svc.deleteUser('u2')).toThrow('db failure')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when role is "Admin" (case-sensitive)', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
    })

    it('returns true when role is a String object equal to "admin" due to == coercion', () => {
      const svc = new UserService()
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin') as unknown as string
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })

    it('returns false when role is missing or undefined', () => {
      const svc = new UserService()
      expect(svc.isAdmin({})).toBe(false)
      expect(svc.isAdmin({ role: undefined })).toBe(false)
    })

    it('returns false for non-string roles that do not coerce to "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 0 as any })).toBe(false)
      expect(svc.isAdmin({ role: true as any })).toBe(false)
      expect(svc.isAdmin({ role: 'admin ' })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      const svc = new UserService()
      global.jwt.decode.mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('token')).toBe(true)
      expect(global.jwt.decode).toHaveBeenCalledWith('token')
    })

    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      global.jwt.decode.mockReturnValue(null)
      expect(svc.validateToken('invalid')).toBe(false)
      expect(global.jwt.decode).toHaveBeenCalledWith('invalid')
    })

    it('throws when jwt.decode throws', () => {
      const svc = new UserService()
      global.jwt.decode.mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => svc.validateToken('bad')).toThrow('decode failed')
    })
  })

  describe('hardcoded secrets accessibility at runtime', () => {
    it('exposes ADMIN_PASSWORD value on instance at runtime', () => {
      const svc = new UserService() as any
      expect(svc.ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY value on instance at runtime', () => {
      const svc = new UserService() as any
      expect(svc.API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})