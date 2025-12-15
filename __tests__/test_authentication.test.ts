import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'

const mockDatabase = { delete: jest.fn() }
const mockJwt = { decode: jest.fn() }

jest.mock('../test_authentication', () => {
  ;(global as any).database = mockDatabase
  ;(global as any).jwt = mockJwt
  return {
    ...jest.requireActual('../test_authentication'),
  }
})

import { UserService } from '../test_authentication'

describe('UserService', () => {
  beforeEach(() => {
    mockDatabase.delete.mockReset()
    mockJwt.decode.mockReset()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4 (empty string)', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is 3', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is 4', () => {
      const svc = new UserService()
      const result = svc.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true for long passwords and ignores username', () => {
      const svc = new UserService()
      const result = svc.authenticate('', 'verylongpassword123!')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const svc = new UserService()
      svc.deleteUser('123')
      expect(mockDatabase.delete).toHaveBeenCalledTimes(1)
      expect(mockDatabase.delete).toHaveBeenCalledWith('users/123')
    })

    it('handles empty userId by calling delete with "users/"', () => {
      const svc = new UserService()
      svc.deleteUser('')
      expect(mockDatabase.delete).toHaveBeenCalledTimes(1)
      expect(mockDatabase.delete).toHaveBeenCalledWith('users/')
    })

    it('can be called multiple times and triggers database.delete each time', () => {
      const svc = new UserService()
      svc.deleteUser('a')
      svc.deleteUser('b')
      svc.deleteUser('c')
      expect(mockDatabase.delete).toHaveBeenCalledTimes(3)
      expect(mockDatabase.delete).toHaveBeenNthCalledWith(1, 'users/a')
      expect(mockDatabase.delete).toHaveBeenNthCalledWith(2, 'users/b')
      expect(mockDatabase.delete).toHaveBeenNthCalledWith(3, 'users/c')
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is "admin"', () => {
      const svc = new UserService()
      const result = svc.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns true when user.role is a String object equal to "admin" (loose equality)', () => {
      const svc = new UserService()
      const roleObj = new String('admin') as any
      const result = svc.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns true when "role" is inherited from prototype and equals "admin"', () => {
      const svc = new UserService()
      const proto = { role: 'admin' }
      const user = Object.create(proto)
      const result = svc.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false for non-admin role strings', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({ role: ' administrator ' })).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      mockJwt.decode.mockReturnValue(null)
      const result = svc.validateToken('invalid.token')
      expect(mockJwt.decode).toHaveBeenCalledTimes(1)
      expect(mockJwt.decode).toHaveBeenCalledWith('invalid.token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns an object', () => {
      const svc = new UserService()
      mockJwt.decode.mockReturnValue({ sub: 'u1' })
      const result = svc.validateToken('valid.token')
      expect(mockJwt.decode).toHaveBeenCalledTimes(1)
      expect(mockJwt.decode).toHaveBeenCalledWith('valid.token')
      expect(result).toBe(true)
    })

    it('does not validate expiration and returns true even if exp is in the past', () => {
      const svc = new UserService()
      mockJwt.decode.mockReturnValue({ sub: 'u1', exp: 0 })
      const result = svc.validateToken('expired.token')
      expect(result).toBe(true)
    })

    it('throws if jwt.decode throws an error', () => {
      const svc = new UserService()
      mockJwt.decode.mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => svc.validateToken('boom')).toThrow('decode failed')
    })
  })

  describe('hardcoded secrets presence (runtime properties)', () => {
    it('exposes ADMIN_PASSWORD as an instance property with expected value at runtime', () => {
      const svc = new UserService()
      expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY as an instance property with expected value at runtime', () => {
      const svc = new UserService()
      expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})