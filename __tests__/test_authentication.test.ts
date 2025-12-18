import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService

  beforeEach(() => {
    ;(global as any).database = {
      delete: jest.fn()
    }
    ;(global as any).jwt = {
      decode: jest.fn()
    }
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false for passwords shorter than 4 chars', () => {
      expect(svc.authenticate('user', 'a')).toBe(false)
      expect(svc.authenticate('user', 'ab')).toBe(false)
      expect(svc.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true for passwords with length >= 4', () => {
      expect(svc.authenticate('user', 'abcd')).toBe(true)
      expect(svc.authenticate('user', 'longpassword')).toBe(true)
    })

    it('ignores username and relies only on password length', () => {
      expect(svc.authenticate('', 'abcd')).toBe(true)
      expect(svc.authenticate('someone', 'abc')).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path', () => {
      svc.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('does not perform any authorization checks', () => {
      svc.deleteUser('targetUser')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/targetUser')
    })

    it('propagates errors thrown by database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw new Error('db failure')
      })
      expect(() => svc.deleteUser('bad')).toThrow('db failure')
    })

    it('supports any string for userId', () => {
      svc.deleteUser('admin')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/admin')

      svc.deleteUser('..//weird//id')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/..//weird//id')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is "admin"', () => {
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('uses loose equality: String object equals "admin"', () => {
      expect(svc.isAdmin({ role: new String('admin') as any })).toBe(true)
    })

    it('returns false for non-admin roles', () => {
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({ role: 'ADMIN' })).toBe(false)
      expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
      expect(svc.isAdmin({ role: '' })).toBe(false)
      expect(svc.isAdmin({})).toBe(false)
      expect(svc.isAdmin({ role: 1 as any })).toBe(false)
      expect(svc.isAdmin({ role: true as any })).toBe(false)
    })

    it('throws when user is null or undefined', () => {
      expect(() => (svc as any).isAdmin(undefined)).toThrow()
      expect(() => (svc as any).isAdmin(null)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '1' })
      expect(svc.validateToken('token')).toBe(true)
      expect((global as any).jwt.decode).toHaveBeenCalledWith('token')
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      expect(svc.validateToken('bad')).toBe(false)
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => svc.validateToken('x')).toThrow('decode error')
    })

    it('works with empty string tokens (returns false when decode returns null)', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      expect(svc.validateToken('')).toBe(false)
    })

    it('returns true even for malformed but decodable tokens (object-like)', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({})
      expect(svc.validateToken('not-a-jwt')).toBe(true)
    })
  })

  describe('hardcoded secrets presence', () => {
    it('exposes ADMIN_PASSWORD at runtime on instance (private at type-level only)', () => {
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY at runtime on instance', () => {
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})