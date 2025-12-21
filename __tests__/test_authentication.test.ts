import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare const global: any

describe('UserService', () => {
  beforeEach(() => {
    global.database = { delete: jest.fn() }
    global.jwt = { decode: jest.fn() }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete global.database
    delete global.jwt
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '123')).toBe(false)
      expect(svc.authenticate('user', '')).toBe(false)
      expect(svc.authenticate('user', '   ')).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const svc = new UserService()
      expect(svc.authenticate('user', '1234')).toBe(true)
    })

    it('returns true when password length is greater than or equal to 4, regardless of username', () => {
      const svc = new UserService()
      expect(svc.authenticate('anyone', 'abcd')).toBe(true)
      expect(svc.authenticate('unknown', 'longpassword')).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const svc = new UserService()
      svc.deleteUser('abc')
      expect(global.database.delete).toHaveBeenCalledTimes(1)
      expect(global.database.delete).toHaveBeenCalledWith('users/abc')
    })

    it('passes through complex userId in the path (including slashes)', () => {
      const svc = new UserService()
      svc.deleteUser('123/456')
      expect(global.database.delete).toHaveBeenCalledWith('users/123/456')
    })

    it('throws if database.delete throws', () => {
      const svc = new UserService()
      const err = new Error('boom')
      global.database.delete.mockImplementation(() => {
        throw err
      })
      expect(() => svc.deleteUser('abc')).toThrow(err)
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'admin' })).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const svc = new UserService()
      expect(svc.isAdmin({ role: 'user' })).toBe(false)
      expect(svc.isAdmin({ role: '' })).toBe(false)
      expect(svc.isAdmin({})).toBe(false)
    })

    it('returns true when user.role is an object coercible to "admin" using ==', () => {
      const svc = new UserService()
      const roleObj = {
        toString() {
          return 'admin'
        }
      }
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })

    it('returns true when user.role is a String object with value "admin"', () => {
      const svc = new UserService()
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin')
      expect(svc.isAdmin({ role: roleObj })).toBe(true)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null payload', () => {
      const svc = new UserService()
      global.jwt.decode.mockReturnValue({ sub: 'u1' })
      expect(svc.validateToken('token')).toBe(true)
      expect(global.jwt.decode).toHaveBeenCalledWith('token')
    })

    it('returns false when jwt.decode returns null', () => {
      const svc = new UserService()
      global.jwt.decode.mockReturnValue(null)
      expect(svc.validateToken('token')).toBe(false)
    })

    it('throws if jwt.decode throws', () => {
      const svc = new UserService()
      global.jwt.decode.mockImplementation(() => {
        throw new Error('decode fail')
      })
      expect(() => svc.validateToken('token')).toThrow('decode fail')
    })
  })

  describe('runtime secrets exposure (actual runtime behavior)', () => {
    it('exposes ADMIN_PASSWORD as a runtime property with the hardcoded value', () => {
      const svc: any = new UserService()
      expect(svc.ADMIN_PASSWORD).toBe('admin123')
    })

    it('exposes API_KEY as a runtime property with the hardcoded value', () => {
      const svc: any = new UserService()
      expect(svc.API_KEY).toBe('sk_live_abc123xyz')
    })
  })
})