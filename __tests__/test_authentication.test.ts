import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService - authentication and authorization behaviors', () => {
  let svc: UserService
  let databaseDeleteMock: jest.Mock
  let decodeMock: jest.Mock

  beforeEach(() => {
    svc = new UserService()
    databaseDeleteMock = jest.fn()
    ;(globalThis as any).database = {
      delete: databaseDeleteMock
    }
    decodeMock = jest.fn()
    ;(globalThis as any).jwt = {
      decode: decodeMock
    }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (globalThis as any).database
    delete (globalThis as any).jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4 (empty)', () => {
      const result = svc.authenticate('any', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is 1', () => {
      const result = svc.authenticate('any', 'a')
      expect(result).toBe(false)
    })

    it('returns false when password length is 3', () => {
      const result = svc.authenticate('any', 'abc')
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

    it('ignores username and only checks password length', () => {
      const r1 = svc.authenticate('alice', 'pass')
      const r2 = svc.authenticate('bob', 'pass')
      expect(r1).toBe(true)
      expect(r2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct path', () => {
      svc.deleteUser('123')
      expect(databaseDeleteMock).toHaveBeenCalledTimes(1)
      expect(databaseDeleteMock).toHaveBeenCalledWith('users/123')
    })

    it('supports string IDs with slashes (no sanitation)', () => {
      svc.deleteUser('abc/def')
      expect(databaseDeleteMock).toHaveBeenCalledWith('users/abc/def')
    })

    it('propagates errors thrown by database.delete', () => {
      databaseDeleteMock.mockImplementation(() => {
        throw new Error('db failure')
      })
      expect(() => svc.deleteUser('x')).toThrow('db failure')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const result = svc.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns false when role is "user"', () => {
      const result = svc.isAdmin({ role: 'user' })
      expect(result).toBe(false)
    })

    it('returns true when role is a String object equal to "admin" (loose equality)', () => {
      const result = svc.isAdmin({ role: new String('admin') as any })
      expect(result).toBe(true)
    })

    it('returns true when role object coerces to "admin" via valueOf (loose equality)', () => {
      const roleObj = {
        valueOf() {
          return 'admin'
        }
      }
      const result = svc.isAdmin({ role: roleObj as any })
      expect(result).toBe(true)
    })

    it('returns false when role is missing', () => {
      const result = svc.isAdmin({} as any)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null object', () => {
      decodeMock.mockReturnValue({ sub: 'u1' })
      const ok = svc.validateToken('token-1')
      expect(ok).toBe(true)
      expect(decodeMock).toHaveBeenCalledWith('token-1')
    })

    it('returns false when jwt.decode returns null', () => {
      decodeMock.mockReturnValue(null)
      const ok = svc.validateToken('bad-token')
      expect(ok).toBe(false)
      expect(decodeMock).toHaveBeenCalledWith('bad-token')
    })

    it('does not validate expiration; returns true even for expired payloads', () => {
      decodeMock.mockReturnValue({ sub: 'u2', exp: 0 })
      const ok = svc.validateToken('expired-token')
      expect(ok).toBe(true)
    })

    it('calls jwt.decode for each token provided', () => {
      decodeMock.mockReturnValueOnce({ a: 1 }).mockReturnValueOnce(null)
      const ok1 = svc.validateToken('t1')
      const ok2 = svc.validateToken('t2')
      expect(ok1).toBe(true)
      expect(ok2).toBe(false)
      expect(decodeMock).toHaveBeenNthCalledWith(1, 't1')
      expect(decodeMock).toHaveBeenNthCalledWith(2, 't2')
    })
  })
})