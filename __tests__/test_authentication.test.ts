import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    ;(global as any).database = { delete: jest.fn() }
    ;(global as any).jwt = { decode: jest.fn() }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is 0', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'password')
      expect(result).toBe(true)
    })

    it('does not depend on username content', () => {
      const result1 = service.authenticate('', 'abcd')
      const result2 = service.authenticate('admin', 'abcd')
      const result3 = service.authenticate('someone@example.com', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
      expect(result3).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path (numeric id)', () => {
      service.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('calls database.delete with the correct user path (string id)', () => {
      service.deleteUser('abc-XYZ_99')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/abc-XYZ_99')
    })

    it('returns undefined (void) after deleting', () => {
      const result = service.deleteUser('user-1')
      expect(result).toBeUndefined()
    })

    it('propagates errors thrown by database.delete', () => {
      const err = new Error('DB failure')
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw err
      })
      expect(() => service.deleteUser('broken')).toThrow(err)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when role is different case', () => {
      const result = service.isAdmin({ role: 'ADMIN' })
      expect(result).toBe(false)
    })

    it('returns false when role is not admin', () => {
      const result = service.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('performs loose equality comparison allowing object coercion to "admin"', () => {
      const coerced = {
        role: {
          toString() {
            return 'admin'
          }
        }
      }
      const result = service.isAdmin(coerced)
      expect(result).toBe(true)
    })

    it('returns false when role is undefined', () => {
      const result = service.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when role is null', () => {
      const result = service.isAdmin({ role: null })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
      const result = service.validateToken('token-1')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('token-2')
      expect(result).toBe(false)
    })

    it('passes the token to jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'abc.def.ghi'
      const result = service.validateToken(token)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
      expect(result).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const err = new Error('decode error')
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw err
      })
      expect(() => service.validateToken('bad')).toThrow(err)
    })

    it('treats non-null falsy values from jwt.decode (e.g., 0) as valid', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(0)
      const result = service.validateToken('token-0')
      expect(result).toBe(true)
    })
  })
})