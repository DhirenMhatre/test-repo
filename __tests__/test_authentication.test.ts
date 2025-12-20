import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService
  const originalJwt = (global as any).jwt
  const originalDatabase = (global as any).database

  beforeEach(() => {
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    if (typeof originalJwt === 'undefined') {
      delete (global as any).jwt
    } else {
      ;(global as any).jwt = originalJwt
    }
    if (typeof originalDatabase === 'undefined') {
      delete (global as any).database
    } else {
      ;(global as any).database = originalDatabase
    }
  })

  describe('authenticate', () => {
    it('returns false when password length < 4 (empty string)', () => {
      const result = svc.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length < 4 (3 chars)', () => {
      const result = svc.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length >= 4', () => {
      const result = svc.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result1 = svc.authenticate('any-username', 'abcd')
      const result2 = svc.authenticate('another-user', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('handles very long passwords', () => {
      const longPwd = 'x'.repeat(1000)
      const result = svc.authenticate('user', longPwd)
      expect(result).toBe(true)
    })

    it('throws TypeError if password is not a string and lacks length', () => {
      expect(() => svc.authenticate('user', 123 as any)).toThrow()
    })
  })

  describe('deleteUser', () => {
    it('throws when database is not defined', () => {
      delete (global as any).database
      expect(() => svc.deleteUser('u1')).toThrow()
    })

    it('calls database.delete with correct path when database exists', () => {
      const del = jest.fn()
      ;(global as any).database = { delete: del }
      svc.deleteUser('u123')
      expect(del).toHaveBeenCalledTimes(1)
      expect(del).toHaveBeenCalledWith('users/u123')
    })

    it('bubbles up errors thrown by database.delete', () => {
      const del = jest.fn(() => {
        throw new Error('db down')
      })
      ;(global as any).database = { delete: del }
      expect(() => svc.deleteUser('u9')).toThrow('db down')
    })

    it('does not sanitize path - passes raw userId', () => {
      const del = jest.fn()
      ;(global as any).database = { delete: del }
      const maliciousId = '../..//etc/passwd'
      svc.deleteUser(maliciousId)
      expect(del).toHaveBeenCalledWith(`users/${maliciousId}`)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const user = { role: 'admin' }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('returns false when role is "user"', () => {
      const user = { role: 'user' }
      expect(svc.isAdmin(user)).toBe(false)
    })

    it('coerces String objects to primitive with == and returns true', () => {
      const user = { role: new String('admin') as any }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('coerces objects via toString and returns true when toString() => "admin"', () => {
      const roleObj = {
        toString: () => 'admin',
        valueOf: () => ({})
      }
      const user = { role: roleObj as any }
      expect(svc.isAdmin(user)).toBe(true)
    })

    it('throws when user is null or undefined', () => {
      expect(() => svc.isAdmin(null as any)).toThrow()
      expect(() => svc.isAdmin(undefined as any)).toThrow()
    })

    it('returns false for similar but not equal strings', () => {
      expect(svc.isAdmin({ role: 'ADMIN' })).toBe(false)
      expect(svc.isAdmin({ role: ' admin' })).toBe(false)
      expect(svc.isAdmin({ role: 'admin ' })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('throws when jwt is not defined', () => {
      delete (global as any).jwt
      expect(() => svc.validateToken('token')).toThrow()
    })

    it('returns true when jwt.decode returns an object', () => {
      const decode = jest.fn().mockReturnValue({ sub: 'u1' })
      ;(global as any).jwt = { decode }
      const result = svc.validateToken('token-123')
      expect(decode).toHaveBeenCalledWith('token-123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const decode = jest.fn().mockReturnValue(null)
      ;(global as any).jwt = { decode }
      const result = svc.validateToken('bad-token')
      expect(decode).toHaveBeenCalledWith('bad-token')
      expect(result).toBe(false)
    })

    it('does not validate expiration - returns true even if exp is in the past', () => {
      const past = Math.floor(Date.now() / 1000) - 1000
      const decode = jest.fn().mockReturnValue({ sub: 'u1', exp: past })
      ;(global as any).jwt = { decode }
      const result = svc.validateToken('expired-token')
      expect(result).toBe(true)
    })
  })

  describe('hardcoded secrets visibility (runtime behavior)', () => {
    it('exposes ADMIN_PASSWORD at runtime despite TypeScript private', () => {
      const secret = (svc as any).ADMIN_PASSWORD
      expect(secret).toBe('admin123')
    })

    it('exposes API_KEY at runtime despite TypeScript private', () => {
      const key = (svc as any).API_KEY
      expect(key).toBe('sk_live_abc123xyz')
    })
  })
})