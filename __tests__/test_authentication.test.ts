import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let databaseDeleteMock: jest.Mock
  let jwtDecodeMock: jest.Mock

  beforeEach(() => {
    service = new UserService()
    databaseDeleteMock = jest.fn()
    ;(globalThis as any).database = { delete: databaseDeleteMock }
    jwtDecodeMock = jest.fn()
    ;(globalThis as any).jwt = { decode: jwtDecodeMock }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (globalThis as any).database
    delete (globalThis as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is 0', () => {
      const result = service.authenticate('any', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is 3', () => {
      const result = service.authenticate('user', 'xyz')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'pass')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longer')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result1 = service.authenticate('alice', 'four')
      const result2 = service.authenticate('bob', 'four')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('treats whitespace-only password by length (passes when length >= 4)', () => {
      const result = service.authenticate('user', '    ')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path for a typical userId', () => {
      service.deleteUser('123')
      expect(databaseDeleteMock).toHaveBeenCalledTimes(1)
      expect(databaseDeleteMock).toHaveBeenCalledWith('users/123')
    })

    it('calls database.delete with userId "0"', () => {
      service.deleteUser('0')
      expect(databaseDeleteMock).toHaveBeenCalledTimes(1)
      expect(databaseDeleteMock).toHaveBeenCalledWith('users/0')
    })

    it('propagates errors thrown by database.delete', () => {
      databaseDeleteMock.mockImplementation(() => {
        throw new Error('db failure')
      })
      expect(() => service.deleteUser('abc')).toThrow('db failure')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is exactly "admin"', () => {
      const result = service.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when user.role is "user"', () => {
      const result = service.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('uses loose equality: returns true when role is a String object "admin"', () => {
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin')
      const result = service.isAdmin({ role: roleObj as unknown as string })
      expect(result).toBe(true)
    })

    it('uses loose equality: returns true when role object coerces to "admin"', () => {
      const trickyRole = {
        toString: () => 'admin',
        valueOf: () => 'nope'
      }
      const result = service.isAdmin({ role: trickyRole as unknown as string })
      expect(result).toBe(true)
    })

    it('is case-sensitive: returns false for "Admin"', () => {
      const result = service.isAdmin({ role: 'Admin' })
      expect(result).toBe(false)
    })

    it('returns false when role is undefined on the object', () => {
      const result = service.isAdmin({} as any)
      expect(result).toBe(false)
    })

    it('throws when user is null (cannot read property "role")', () => {
      expect(() => service.isAdmin(null as any)).toThrow()
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      jwtDecodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('token-abc')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('token-abc')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('bad-token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('bad-token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns undefined (due to !== null check)', () => {
      jwtDecodeMock.mockReturnValue(undefined)
      const result = service.validateToken('weird-token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('weird-token')
      expect(result).toBe(true)
    })

    it('passes the token string directly to jwt.decode', () => {
      jwtDecodeMock.mockReturnValue({ any: 'value' })
      const token = ''
      const result = service.validateToken(token)
      expect(jwtDecodeMock).toHaveBeenCalledWith('')
      expect(result).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      jwtDecodeMock.mockImplementation(() => {
        throw new Error('decode error')
      })
      expect(() => service.validateToken('x')).toThrow('decode error')
    })
  })
})