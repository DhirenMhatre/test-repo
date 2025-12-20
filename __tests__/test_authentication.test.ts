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
    it('returns false when password length is less than 4 (0 length)', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4 (3 length)', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longpassword123')
      expect(result).toBe(true)
    })

    it('ignores username and bases result solely on password length', () => {
      const ok = service.authenticate('', '1234')
      const notOk = service.authenticate('anyuser', '123')
      expect(ok).toBe(true)
      expect(notOk).toBe(false)
    })

    it('returns consistent results across multiple calls (no rate limiting)', () => {
      const r1 = service.authenticate('u1', 'pass')
      const r2 = service.authenticate('u2', 'pass')
      const r3 = service.authenticate('u3', 'bad')
      expect(r1).toBe(true)
      expect(r2).toBe(true)
      expect(r3).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path', () => {
      service.deleteUser('123')
      expect((global as any).database.delete).toHaveBeenCalledTimes(1)
      expect((global as any).database.delete).toHaveBeenCalledWith('users/123')
    })

    it('propagates errors thrown by database.delete', () => {
      ;((global as any).database.delete as jest.Mock).mockImplementation(() => {
        throw new Error('fail')
      })
      expect(() => service.deleteUser('999')).toThrow('fail')
    })

    it('supports multiple deletions with correct paths', () => {
      service.deleteUser('a')
      service.deleteUser('b')
      service.deleteUser('c')
      expect((global as any).database.delete).toHaveBeenNthCalledWith(1, 'users/a')
      expect((global as any).database.delete).toHaveBeenNthCalledWith(2, 'users/b')
      expect((global as any).database.delete).toHaveBeenNthCalledWith(3, 'users/c')
      expect((global as any).database.delete).toHaveBeenCalledTimes(3)
    })

    it('passes userId verbatim even if it contains slashes or special characters', () => {
      const id = 'weird/id?param=1'
      service.deleteUser(id)
      expect((global as any).database.delete).toHaveBeenCalledWith(`users/${id}`)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      const result = service.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('uses == comparison: returns true for new String("admin")', () => {
      const result = service.isAdmin({ role: new String('admin') as any })
      expect(result).toBe(true)
    })

    it('returns false when role is missing', () => {
      const result = service.isAdmin({} as any)
      expect(result).toBe(false)
    })

    it('returns true when role is inherited via prototype and equals "admin"', () => {
      const proto = { role: 'admin' }
      const obj = Object.create(proto)
      const result = service.isAdmin(obj)
      expect(result).toBe(true)
    })

    it('throws when user is null', () => {
      expect(() => service.isAdmin(null as any)).toThrow()
    })

    it('throws when user is undefined', () => {
      expect(() => service.isAdmin(undefined as any)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ sub: '1' })
      const result = service.validateToken('token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('invalid')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns undefined because check is !== null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(undefined)
      const result = service.validateToken('weird')
      expect(result).toBe(true)
    })

    it('propagates error when jwt.decode throws', () => {
      ;((global as any).jwt.decode as jest.Mock).mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('bad')).toThrow('decode error')
    })

    it('calls jwt.decode with the provided token', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue({ ok: true })
      const token = 'abc.def.ghi'
      const result = service.validateToken(token)
      expect(result).toBe(true)
      expect((global as any).jwt.decode).toHaveBeenCalledWith(token)
    })

    it('handles empty string token as false if decode returns null', () => {
      ;((global as any).jwt.decode as jest.Mock).mockReturnValue(null)
      const result = service.validateToken('')
      expect(result).toBe(false)
      expect((global as any).jwt.decode).toHaveBeenCalledWith('')
    })
  })
})