import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  beforeEach(() => {
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn() }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', '123')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true and ignores username when password is long enough', () => {
      const svc = new UserService()
      const result = svc.authenticate('', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for whitespace-only password of length 4 (no trimming)', () => {
      const svc = new UserService()
      const result = svc.authenticate('any', '    ')
      expect(result).toBe(true)
    })

    it('returns true for long password', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', 'verylongpassword')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with expected path', () => {
      const svc = new UserService()
      const del = (global as any).database.delete as jest.Mock
      svc.deleteUser('u123')
      expect(del).toHaveBeenCalledTimes(1)
      expect(del).toHaveBeenCalledWith('users/u123')
    })

    it('accepts arbitrary userId strings', () => {
      const svc = new UserService()
      const del = (global as any).database.delete as jest.Mock
      svc.deleteUser('../etc/passwd')
      expect(del).toHaveBeenCalledWith('users/../etc/passwd')
    })

    it('propagates errors thrown by database.delete', () => {
      const svc = new UserService()
      const del = (global as any).database.delete as jest.Mock
      del.mockImplementation(() => {
        throw new Error('DB_FAIL')
      })
      expect(() => svc.deleteUser('oops')).toThrow('DB_FAIL')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is "admin"', () => {
      const svc = new UserService()
      const user = { role: 'admin' }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const svc = new UserService()
      const user = { role: 'user' }
      expect(svc.isAdmin(user)).toBe(false)
    })

    it('returns true when role is a String object equal to "admin" due to loose equality', () => {
      const svc = new UserService()
      const user = { role: new String('admin') as unknown as string }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('returns true when role object coerces to "admin" via toString (loose equality)', () => {
      const svc = new UserService()
      const roleObj = {
        toString: () => 'admin'
      }
      const user = { role: roleObj as unknown as string }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('is case sensitive; returns false for "Admin"', () => {
      const svc = new UserService()
      const user = { role: 'Admin' }
      expect(svc.isAdmin(user)).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a payload object', () => {
      const svc = new UserService()
      const decode = (global as any).jwt.decode as jest.Mock
      decode.mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('token')).toBe(true)
      expect(decode).toHaveBeenCalledWith('token')
    })

    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      const decode = (global as any).jwt.decode as jest.Mock
      decode.mockReturnValue(null)
      expect(svc.validateToken('badtoken')).toBe(false)
    })

    it('does not validate expiration; returns true even if payload is expired', () => {
      const svc = new UserService()
      const decode = (global as any).jwt.decode as jest.Mock
      const past = Math.floor(Date.now() / 1000) - 3600
      decode.mockReturnValue({ exp: past, sub: 'u2' })
      expect(svc.validateToken('expiredToken')).toBe(true)
    })

    it('does not verify signature; returns true when decode returns object regardless of token', () => {
      const svc = new UserService()
      const decode = (global as any).jwt.decode as jest.Mock
      decode.mockReturnValue({ sub: 'u3' })
      expect(svc.validateToken('invalidSignatureToken')).toBe(true)
    })

    it('treats non-null falsy values as valid (strict non-null check)', () => {
      const svc = new UserService()
      const decode = (global as any).jwt.decode as jest.Mock
      decode.mockReturnValue(0)
      expect(svc.validateToken('zeroPayload')).toBe(true)
    })
  })

  describe('hardcoded fields runtime presence', () => {
    it('exposes ADMIN_PASSWORD at runtime (TS private is not enforced at runtime)', () => {
      const svc = new UserService()
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY at runtime with expected value', () => {
      const svc = new UserService()
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})