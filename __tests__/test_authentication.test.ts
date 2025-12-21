import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService

  beforeEach(() => {
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn() }
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = svc.authenticate('user', '123')
      expect(result).toBe(false)
    })

    it('returns false when password is empty', () => {
      const result = svc.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = svc.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = svc.authenticate('user', 'longpassword')
      expect(result).toBe(true)
    })

    it('ignores the username and only checks password length', () => {
      const result1 = svc.authenticate('', 'abcd')
      const result2 = svc.authenticate('any-username', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path for string id', () => {
      svc.deleteUser('abc')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/abc')
    })

    it('calls database.delete with the correct path for numeric id', () => {
      svc.deleteUser(String(123))
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('does not perform any authorization checks (always calls delete)', () => {
      svc.deleteUser('victim')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/victim')
    })

    it('propagates errors thrown by database.delete', () => {
      const err = new Error('db failure')
      ;(global as any).database.delete.mockImplementation(() => {
        throw err
      })
      expect(() => svc.deleteUser('any')).toThrow(err)
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      const result = svc.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('uses == so returns true when role is a String object "admin"', () => {
      const roleObj = new String('admin') as any
      const result = svc.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns true when role object coerces to "admin" via toString', () => {
      const roleObj = { toString: () => 'admin' }
      const result = svc.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns false when role is not "admin" (case-sensitive)', () => {
      const result = svc.isAdmin({ role: 'ADMIN' })
      expect(result).toBe(false)
    })

    it('returns false when role is undefined', () => {
      const result = svc.isAdmin({ })
      expect(result).toBe(false)
    })

    it('throws when user is null', () => {
      expect(() => svc.isAdmin(null as any)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null payload', () => {
      ;(global as any).jwt.decode.mockReturnValue({ sub: 'u1' })
      const ok = svc.validateToken('token-123')
      expect(ok).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;(global as any).jwt.decode.mockReturnValue(null)
      const ok = svc.validateToken('token-xyz')
      expect(ok).toBe(false)
    })

    it('calls jwt.decode with the provided token', () => {
      ;(global as any).jwt.decode.mockReturnValue({ any: 'value' })
      const token = 'my-token'
      svc.validateToken(token)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const err = new Error('decode failed')
      ;(global as any).jwt.decode.mockImplementation(() => {
        throw err
      })
      expect(() => svc.validateToken('bad-token')).toThrow(err)
    })
  })
})