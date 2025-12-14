import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
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
      const res = service.authenticate('user', 'abc')
      expect(res).toBe(false)
    })

    it('returns false when password is empty', () => {
      const res = service.authenticate('user', '')
      expect(res).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const res = service.authenticate('user', 'abcd')
      expect(res).toBe(true)
    })

    it('returns true when password length is greater than 4 regardless of username', () => {
      const res = service.authenticate('', 'abcdef')
      expect(res).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the expected user path', () => {
      service.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('returns undefined (void) after calling database.delete', () => {
      const result = service.deleteUser('999')
      expect(result).toBeUndefined()
    })

    it('propagates errors thrown from database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementationOnce(() => {
        throw new Error('DB failure')
      })
      expect(() => service.deleteUser('err')).toThrow('DB failure')
    })

    it('supports arbitrary string userIds', () => {
      service.deleteUser('user-abc_001')
      expect((global as any).database.delete).toHaveBeenCalledWith('users/user-abc_001')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is "admin"', () => {
      const res = service.isAdmin({ role: 'admin' })
      expect(res).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      const res = service.isAdmin({ role: 'user' })
      expect(res).toBe(false)
    })

    it('uses loose equality allowing objects that coerce to "admin"', () => {
      const user = { role: { toString: () => 'admin' } }
      const res = service.isAdmin(user)
      expect(res).toBe(true)
    })

    it('is case-sensitive and returns false for "ADMIN"', () => {
      const res = service.isAdmin({ role: 'ADMIN' })
      expect(res).toBe(false)
    })

    it('throws when user is null or undefined', () => {
      expect(() => service.isAdmin(null as any)).toThrow()
      expect(() => service.isAdmin(undefined as any)).toThrow()
    })

    it('returns true when role is a String object with value "admin"', () => {
      const res = service.isAdmin({ role: new String('admin') })
      expect(res).toBe(true)
    })

    it('returns false when role is a number or boolean', () => {
      expect(service.isAdmin({ role: 1 })).toBe(false)
      expect(service.isAdmin({ role: true })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a payload object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
      const res = service.validateToken('token')
      expect(res).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const res = service.validateToken('token')
      expect(res).toBe(false)
    })

    it('returns true when jwt.decode returns a non-null falsy value like empty string', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue('')
      const res = service.validateToken('token')
      expect(res).toBe(true)
    })

    it('calls jwt.decode with the provided token', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'abc.def.ghi'
      service.validateToken(token)
      expect((global as any).jwt.decode).toHaveBeenCalledTimes(1)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })

    it('propagates errors thrown by jwt.decode', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('invalid token')
      })
      expect(() => service.validateToken('bad')).toThrow('invalid token')
    })
  })
})