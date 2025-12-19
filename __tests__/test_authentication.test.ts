import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  beforeEach(() => {
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn(() => ({})) }
  })

  afterEach(() => {
    delete (global as any).database
    delete (global as any).jwt
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length < 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length == 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length > 4 regardless of username', () => {
      const svc = new UserService()
      const result1 = svc.authenticate('user1', 'abcdef')
      const result2 = svc.authenticate('', 'longpassword')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const svc = new UserService()
      svc.deleteUser('u123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/u123')
    })

    it('formats path correctly for different user IDs', () => {
      const svc = new UserService()
      svc.deleteUser('abc-123')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/abc-123')
    })

    it('returns undefined (void) after calling delete', () => {
      const svc = new UserService()
      const ret = svc.deleteUser('u1')
      expect(ret).toBeUndefined()
    })

    it('propagates errors thrown by database.delete', () => {
      ;(global as any).database.delete.mockImplementation(() => {
        throw new Error('db down')
      })
      const svc = new UserService()
      expect(() => svc.deleteUser('u1')).toThrow('db down')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns true when user.role is a String object with "admin"', () => {
      const svc = new UserService()
      const roleObj = new String('admin') as unknown as string
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })

    it('returns true when user.role object toString returns "admin"', () => {
      const svc = new UserService()
      const roleLike = { toString: () => 'admin' }
      expect(svc.isAdmin({ role: roleLike as unknown as string })).toBe(true)
    })

    it('returns false when role is "Admin" (case-sensitive check)', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
    })

    it('returns false for non-admin roles', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({ role: undefined })).toBe(false)
      expect(svc.isAdmin({})).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      ;(global as any).jwt.decode.mockReturnValue({ sub: 'u1' })
      const svc = new UserService()
      const result = svc.validateToken('token-123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;(global as any).jwt.decode.mockReturnValue(null)
      const svc = new UserService()
      const result = svc.validateToken('bad-token')
      expect(result).toBe(false)
    })

    it('calls jwt.decode with the provided token', () => {
      const svc = new UserService()
      const token = 'abc.def.ghi'
      svc.validateToken(token)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;(global as any).jwt.decode.mockImplementation(() => {
        throw new Error('decode failure')
      })
      const svc = new UserService()
      expect(() => svc.validateToken('any-token')).toThrow('decode failure')
    })
  })

  describe('hardcoded properties (runtime presence)', () => {
    it('has ADMIN_PASSWORD with expected value at runtime', () => {
      const svc = new UserService() as any
      expect(svc.ADMIN_PASSWORD).toBe('admin123')
    })

    it('has API_KEY with expected value at runtime', () => {
      const svc = new UserService() as any
      expect(svc.API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})