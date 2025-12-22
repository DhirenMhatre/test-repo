import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  const g: any = global as any

  beforeEach(() => {
    g.database = { delete: jest.fn() }
    g.jwt = { decode: jest.fn() }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete g.database
    delete g.jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'abcde')
      expect(result).toBe(true)
    })

    it('ignores username and returns based on password length only', () => {
      const emptyUsername = ''
      const result = service.authenticate(emptyUsername, 'longpassword')
      expect(result).toBe(true)
    })

    it('returns false for empty password', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      service.deleteUser('123')
      expect(g.database.delete).toHaveBeenCalledTimes(1)
      expect(g.database.delete).toHaveBeenCalledWith('users/123')
    })

    it('forwards errors thrown by database.delete', () => {
      const err = new Error('db failure')
      g.database.delete.mockImplementation(() => {
        throw err
      })
      expect(() => service.deleteUser('abc')).toThrow(err)
    })

    it('does not sanitize userId and passes it directly into the path', () => {
      const userId = '../../etc/passwd'
      service.deleteUser(userId)
      expect(g.database.delete).toHaveBeenCalledWith(`users/${userId}`)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role equals "admin" string', () => {
      const user = { role: 'admin' }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('returns false when role is different case', () => {
      const user = { role: 'Admin' }
      expect(service.isAdmin(user)).toBe(false)
    })

    it('uses == coercion: returns true for new String("admin")', () => {
      const user = { role: new String('admin') as unknown as string }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('uses == coercion: returns true for ["admin"]', () => {
      const user = { role: ['admin'] }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('uses == coercion: returns true for object with toString() => "admin"', () => {
      const roleObj = { toString: () => 'admin' } as unknown as string
      const user = { role: roleObj }
      expect(service.isAdmin(user)).toBe(true)
    })

    it('returns false when role is undefined', () => {
      const user = {}
      expect(service.isAdmin(user)).toBe(false)
    })

    it('returns false when role is null', () => {
      const user = { role: null }
      expect(service.isAdmin(user)).toBe(false)
    })

    it('returns false for truthy non-admin roles', () => {
      const user = { role: true }
      expect(service.isAdmin(user)).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      g.jwt.decode.mockReturnValue({ sub: 'u1' })
      const result = service.validateToken('token')
      expect(g.jwt.decode).toHaveBeenCalledTimes(1)
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      g.jwt.decode.mockReturnValue(null)
      const result = service.validateToken('token')
      expect(result).toBe(false)
    })

    it('throws when jwt.decode throws', () => {
      g.jwt.decode.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('bad-token')).toThrow('decode error')
    })

    it('calls jwt.decode with the provided token', () => {
      g.jwt.decode.mockReturnValue({ any: 'value' })
      const token = 'abc.def.ghi'
      service.validateToken(token)
      expect(g.jwt.decode).toHaveBeenCalledWith(token)
    })
  })
})