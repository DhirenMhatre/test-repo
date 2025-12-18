import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService
  let deleteMock: jest.Mock
  let decodeMock: jest.Mock

  beforeEach(() => {
    deleteMock = jest.fn()
    decodeMock = jest.fn()
    ;(global as any).database = { delete: deleteMock }
    ;(global as any).jwt = { decode: decodeMock }
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
    delete (global as any).jwt
  })

  describe('authenticate', () => {
    it.each([
      ['', false],
      ['abc', false],
      ['abcd', true],
      ['    ', true],
      ['verylongpassword', true]
    ])('returns %p for password length case -> %p', (password, expected) => {
      const result = service.authenticate('anyuser', password as string)
      expect(result).toBe(expected)
    })

    it('ignores username and only checks password length', () => {
      const result1 = service.authenticate('unknown-user@example.com', 'abcd')
      const result2 = service.authenticate('', 'abcd')
      const result3 = service.authenticate('admin', 'abc')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
      expect(result3).toBe(false)
    })

    it('consistent result across multiple attempts with same password length', () => {
      const pass = 'abcd'
      const attempt1 = service.authenticate('u', pass)
      const attempt2 = service.authenticate('u', pass)
      const attempt3 = service.authenticate('u', pass)
      expect(attempt1).toBe(true)
      expect(attempt2).toBe(true)
      expect(attempt3).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path', () => {
      service.deleteUser('42')
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith('users/42')
    })

    it('passes userId through as-is (no sanitization)', () => {
      service.deleteUser('../hack')
      expect(deleteMock).toHaveBeenCalledWith('users/../hack')
    })

    it('propagates errors thrown by database.delete', () => {
      const err = new Error('db down')
      deleteMock.mockImplementation(() => {
        throw err
      })
      expect(() => service.deleteUser('7')).toThrow(err)
    })

    it('returns undefined when delete succeeds', () => {
      const result = service.deleteUser('100')
      expect(result).toBeUndefined()
      expect(deleteMock).toHaveBeenCalledWith('users/100')
    })
  })

  describe('isAdmin', () => {
    it('returns true for role "admin" (string)', () => {
      expect(service.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns true for role loosely equal to "admin" (String object)', () => {
      const roleObj = new String('admin') as unknown as string
      expect(service.isAdmin({ role: roleObj as any })).toBe(true)
    })

    it('returns true when role object toString() yields "admin"', () => {
      const weirdRole = { toString: () => 'admin' } as any
      expect(service.isAdmin({ role: weirdRole })).toBe(true)
    })

    it('returns false for non-admin roles and undefined', () => {
      expect(service.isAdmin({ role: 'user' })).toBe(false)
      expect(service.isAdmin({})).toBe(false)
      expect(service.isAdmin({ role: 'Admin' })).toBe(false)
      expect(service.isAdmin({ role: 'administrator' })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns an object', () => {
      decodeMock.mockReturnValue({})
      const result = service.validateToken('token-1')
      expect(result).toBe(true)
      expect(decodeMock).toHaveBeenCalledWith('token-1')
      expect(decodeMock).toHaveBeenCalledTimes(1)
    })

    it('returns true even if decoded payload has expired exp field (no expiry validation)', () => {
      decodeMock.mockReturnValue({ exp: 0 })
      const result = service.validateToken('expired-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      decodeMock.mockReturnValue(null)
      const result = service.validateToken('bad-token')
      expect(result).toBe(false)
    })

    it('propagates error if jwt.decode throws', () => {
      const err = new Error('decode failure')
      decodeMock.mockImplementation(() => {
        throw err
      })
      expect(() => service.validateToken('x')).toThrow(err)
    })

    it('passes the exact token to jwt.decode', () => {
      decodeMock.mockReturnValue({ ok: true })
      const token = 'abc.def.ghi'
      service.validateToken(token)
      expect(decodeMock).toHaveBeenCalledWith(token)
    })
  })
})