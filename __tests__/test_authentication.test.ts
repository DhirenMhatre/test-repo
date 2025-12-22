import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    ;(global as any).database = {
      delete: jest.fn()
    }
    ;(global as any).jwt = {
      decode: jest.fn()
    }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 3', () => {
      const result = service.authenticate('anyuser', 'longpassword')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result = service.authenticate('', 'abcd')
      expect(result).toBe(true)
    })

    it('returns false for whitespace-only password shorter than 4', () => {
      const result = service.authenticate('user', '   ')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with users/{userId}', () => {
      service.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('does not perform any authorization check (always calls delete)', () => {
      service.deleteUser('any-user')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/any-user')
    })

    it('propagates errors thrown by database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw new Error('db failure')
      })
      expect(() => service.deleteUser('u1')).toThrow('db failure')
    })

    it('handles empty userId by calling delete with "users/"', () => {
      service.deleteUser('')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/')
    })

    it('does not sanitize userId path (passes through slashes)', () => {
      service.deleteUser('a/b')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/a/b')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const result = service.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('uses loose equality: returns true when role is a String object "admin"', () => {
      const result = service.isAdmin({ role: new String('admin') as any })
      expect(result).toBe(true)
    })

    it('uses loose equality: returns true when role is an object coercible to "admin"', () => {
      const adminLike = {
        valueOf: () => 'admin',
        toString: () => 'admin'
      }
      const result = service.isAdmin({ role: adminLike })
      expect(result).toBe(true)
    })

    it('returns false when user.role is undefined', () => {
      const result = service.isAdmin({})
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '1' })
      const result = service.validateToken('token-123')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(result).toBe(false)
    })

    it('passes token to jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ any: true })
      const token = 'abc.def.ghi'
      const result = service.validateToken(token)
      expect(result).toBe(true)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })

    it('does not check expiration: returns true for decoded payload with past exp', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ exp: 0, sub: 'u' })
      const result = service.validateToken('expired-token')
      expect(result).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('bad')).toThrow('decode error')
    })
  })
})