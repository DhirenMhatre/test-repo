import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false for passwords shorter than 4 characters', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '123')).toBe(false)
      expect(svc.authenticate('user', '')).toBe(false)
      expect(svc.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true for passwords with length >= 4 regardless of username', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '1234')).toBe(true)
      expect(svc.authenticate('', 'abcd')).toBe(true)
      expect(svc.authenticate('another', 'longpassword')).toBe(true)
    })

    it('does not enforce any username check - username ignored', () => {
      const svc = new UserService()
      expect(svc.authenticate('doesnotmatter', 'pass')).toBe(true)
      expect(svc.authenticate('someone', 'pass')).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path and returns undefined', () => {
      const mockDelete = jest.fn()
      ;(global as any).database = { delete: mockDelete }
      const svc = new UserService()
      const result = svc.deleteUser('123')
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith('users/123')
      expect(result).toBeUndefined()
    })

    it('uses provided userId as-is when building the path', () => {
      const mockDelete = jest.fn()
      ;(global as any).database = { delete: mockDelete }
      const svc = new UserService()
      svc.deleteUser('0')
      expect(mockDelete).toHaveBeenCalledWith('users/0')
      svc.deleteUser('user-xyz')
      expect(mockDelete).toHaveBeenCalledWith('users/user-xyz')
    })

    it('propagates errors thrown by database.delete', () => {
      const err = new Error('delete failed')
      const mockDelete = jest.fn(() => {
        throw err
      })
      ;(global as any).database = { delete: mockDelete }
      const svc = new UserService()
      expect(() => svc.deleteUser('bad-id')).toThrow(err)
      expect(mockDelete).toHaveBeenCalledWith('users/bad-id')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly the string "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
    })

    it('coerces objects to string using == and may return true for String objects', () => {
      const svc = new UserService()
      // Using new String('admin') to leverage == coercion
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin') as any
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })

    it('coerces using toString when role is an object', () => {
      const svc = new UserService()
      const roleLike = {
        toString: () => 'admin',
        valueOf: () => ({}) // ensure toString is used
      }
      expect(svc.isAdmin({ role: roleLike })).toBe(true)
    })

    it('returns false for different casing or non-matching values', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
      expect(svc.isAdmin({ role: 'administrator' })).toBe(false)
      expect(svc.isAdmin({ role: true as any })).toBe(false)
      expect(svc.isAdmin({} as any)).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      const mockDecode = jest.fn().mockReturnValue({ sub: 'u1' })
      ;(global as any).jwt = { decode: mockDecode }
      const svc = new UserService()
      expect(svc.validateToken('token-abc')).toBe(true)
      expect(mockDecode).toHaveBeenCalledTimes(1)
    })

    it('returns false when jwt.decode returns null', () => {
      const mockDecode = jest.fn().mockReturnValue(null)
      ;(global as any).jwt = { decode: mockDecode }
      const svc = new UserService()
      expect(svc.validateToken('bad.token')).toBe(false)
    })

    it('returns true even if jwt.decode returns a string', () => {
      const mockDecode = jest.fn().mockReturnValue('header.payload.signature')
      ;(global as any).jwt = { decode: mockDecode }
      const svc = new UserService()
      expect(svc.validateToken('any')).toBe(true)
    })

    it('passes the token to jwt.decode exactly once', () => {
      const mockDecode = jest.fn().mockReturnValue({ foo: 'bar' })
      ;(global as any).jwt = { decode: mockDecode }
      const svc = new UserService()
      const token = 'xyz.abc.123'
      svc.validateToken(token)
      expect(mockDecode).toHaveBeenCalledTimes(1)
      expect(mockDecode).toHaveBeenCalledWith(token)
    })

    it('does not validate expiration; returns true even if exp is in the past', () => {
      const mockDecode = jest.fn().mockReturnValue({ exp: 1, sub: 'u' })
      ;(global as any).jwt = { decode: mockDecode }
      const svc = new UserService()
      expect(svc.validateToken('expired')).toBe(true)
    })
  })

  describe('hardcoded secrets presence', () => {
    it('exposes ADMIN_PASSWORD field at runtime with expected value', () => {
      const svc = new UserService()
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY field at runtime with expected value', () => {
      const svc = new UserService()
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })

    it('the hardcoded values are consistent across instances', () => {
      const svc1 = new UserService()
      const svc2 = new UserService()
      expect((svc1 as any).ADMIN_PASSWORD).toBe((svc2 as any).ADMIN_PASSWORD)
      expect((svc1 as any).API_KEY).toBe((svc2 as any).API_KEY)
    })
  })
})