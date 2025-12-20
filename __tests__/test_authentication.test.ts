import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService

  beforeEach(() => {
    ;(global as any).database = {
      delete: jest.fn()
    }
    ;(global as any).jwt = {
      decode: jest.fn(() => ({ payload: true })),
      verify: jest.fn()
    }
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      expect(svc.authenticate('user', '')).toBe(false)
      expect(svc.authenticate('user', 'abc')).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      expect(svc.authenticate('user', '1234')).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      expect(svc.authenticate('user', '12345')).toBe(true)
      expect(svc.authenticate('user', 'x'.repeat(100))).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      expect(svc.authenticate('', '1234')).toBe(true)
      expect(svc.authenticate('anyone', '   ')).toBe(false) // length 3
      expect(svc.authenticate('anyone', '    ')).toBe(true) // length 4
    })
  })

  describe('deleteUser', () => {
    it('calls global database.delete with the correct path', () => {
      svc.deleteUser('42')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/42')
    })

    it('propagates errors thrown by database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw new Error('DB failure')
      })
      expect(() => svc.deleteUser('bad-id')).toThrow('DB failure')
    })

    it('uses userId verbatim in the path', () => {
      const trickyId = 'u/../evil'
      svc.deleteUser(trickyId)
      expect((global as any).database.delete).toHaveBeenCalledWith(`users/${trickyId}`)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false for non-admin roles or different case', () => {
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({ role: 'ADMIN' })).toBe(false)
      expect(svc.isAdmin({ role: '' })).toBe(false)
    })

    it('returns true due to loose equality for new String("admin")', () => {
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin')
      expect(svc.isAdmin({ role: roleObj as any })).toBe(true)
    })

    it('returns true when role is an object coercing to "admin"', () => {
      const roleWeird = {
        toString() {
          return 'admin'
        }
      }
      expect(svc.isAdmin({ role: roleWeird as any })).toBe(true)
    })

    it('returns false when role is null or undefined', () => {
      expect(svc.isAdmin({ role: null as any })).toBe(false)
      expect(svc.isAdmin({ role: undefined as any })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null payload', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('valid-token')).toBe(true)
      expect((global as any).jwt.decode).toHaveBeenCalledWith('valid-token')
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      expect(svc.validateToken('invalid-token')).toBe(false)
      expect((global as any).jwt.decode).toHaveBeenCalledWith('invalid-token')
    })

    it('does not call jwt.verify', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ any: true })
      expect(svc.validateToken('any-token')).toBe(true)
      expect((global as any).jwt.verify).not.toHaveBeenCalled()
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => svc.validateToken('boom')).toThrow('decode failed')
    })
  })

  describe('hardcoded secrets presence (runtime behavior)', () => {
    it('exposes ADMIN_PASSWORD as an instance property at runtime', () => {
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY as an instance property at runtime', () => {
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})