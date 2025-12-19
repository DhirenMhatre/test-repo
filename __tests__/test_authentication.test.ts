import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  beforeEach(() => {
    ;(global as any).database = {
      delete: jest.fn()
    }
    ;(global as any).jwt = {
      decode: jest.fn(() => ({ sub: 'user' }))
    }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is 0', () => {
      const svc = new UserService()
      const result = svc.authenticate('any', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is 3', () => {
      const svc = new UserService()
      const result = svc.authenticate('any', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4 and ignores username', () => {
      const svc = new UserService()
      const result = svc.authenticate('nonexistent_user', 'longpassword')
      expect(result).toBe(true)
    })

    it('returns true even when password is spaces as long as length >= 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', '    ')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct path for given user id', () => {
      const svc = new UserService()
      svc.deleteUser('u123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/u123')
    })

    it('coerces non-string userId to string when building path', () => {
      const svc = new UserService()
      ;(svc as any).deleteUser(42 as any)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/42')
    })

    it('propagates error thrown by database.delete', () => {
      const svc = new UserService()
      ;(global as any).database.delete = jest.fn(() => {
        throw new Error('db failure')
      })
      expect(() => svc.deleteUser('broken')).toThrow('db failure')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is string "admin"', () => {
      const svc = new UserService()
      const res = svc.isAdmin({ role: 'admin' })
      expect(res).toBe(true)
    })

    it('returns false when role is different case (e.g., "ADMIN")', () => {
      const svc = new UserService()
      const res = svc.isAdmin({ role: 'ADMIN' })
      expect(res).toBe(false)
    })

    it('returns true when role is a String object wrapping "admin"', () => {
      const svc = new UserService()
      const role = new String('admin') as unknown as string
      const res = svc.isAdmin({ role })
      expect(res).toBe(true)
    })

    it('returns true when role object toString() returns "admin" (due to == coercion)', () => {
      const svc = new UserService()
      const roleObj = {
        toString: () => 'admin'
      } as unknown as string
      const res = svc.isAdmin({ role: roleObj })
      expect(res).toBe(true)
    })

    it('throws TypeError when user is null', () => {
      const svc = new UserService()
      expect(() => svc.isAdmin(null as any)).toThrow(TypeError)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object and passes token through', () => {
      const svc = new UserService()
      const token = 'header.payload.signature'
      ;(global as any).jwt.decode = jest.fn(() => ({ sub: 'abc' }))
      const res = svc.validateToken(token)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
      expect(res).toBe(true)
    })

    it('returns true when jwt.decode returns a string payload', () => {
      const svc = new UserService()
      ;(global as any).jwt.decode = jest.fn(() => 'string-payload')
      const res = svc.validateToken('any.token')
      expect(res).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      ;(global as any).jwt.decode = jest.fn(() => null)
      const res = svc.validateToken('invalid')
      expect(res).toBe(false)
    })

    it('propagates if jwt.decode throws an error', () => {
      const svc = new UserService()
      ;(global as any).jwt.decode = jest.fn(() => {
        throw new Error('decode error')
      })
      expect(() => svc.validateToken('bad.token')).toThrow('decode error')
    })

    it('throws ReferenceError if jwt is not defined', () => {
      const svc = new UserService()
      delete (global as any).jwt
      expect(() => svc.validateToken('token')).toThrow(ReferenceError)
    })
  })

  describe('hardcoded secrets presence', () => {
    it('exposes ADMIN_PASSWORD at runtime due to TS private being compile-time only', () => {
      const svc = new UserService()
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY at runtime', () => {
      const svc = new UserService()
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})