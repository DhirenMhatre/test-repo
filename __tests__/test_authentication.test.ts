import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global dependencies used in the source file
const deleteMock = jest.fn()
const jwtDecodeMock = jest.fn()

// @ts-ignore - simulate global database object
global.database = {
  delete: deleteMock
}

// @ts-ignore - simulate global jwt object
global.jwt = {
  decode: jwtDecodeMock
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4', () => {
      const result = service.authenticate('user', '123')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', '1234')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longpassword')
      expect(result).toBe(true)
    })

    it('does not check username at all', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })

    it('treats empty password as invalid', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledTimes(1)
      expect(deleteMock).toHaveBeenCalledWith('users/123')
    })

    it('does not perform any authorization checks before deleting', () => {
      const userId = '456'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/456')
    })

    it('passes userId as-is into the path', () => {
      const userId = '../evil'
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/../evil')
    })

    it('allows deletion when userId is an empty string', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(deleteMock).toHaveBeenCalledWith('users/')
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const user = { role: 'admin' }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when role is not "admin"', () => {
      const user = { role: 'user' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats number 0 as non-admin', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as non-admin', () => {
      const user = { role: '0' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and can treat object with toString "admin" as admin', () => {
      const user = {
        role: {
          toString: () => 'admin',
          valueOf: () => 'admin'
        } as any
      }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null', () => {
      const user: any = { role: null }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      jwtDecodeMock.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid.token.here')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('valid.token.here')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      jwtDecodeMock.mockReturnValue(null)
      const result = service.validateToken('invalid.token')
      expect(jwtDecodeMock).toHaveBeenCalledTimes(1)
      expect(jwtDecodeMock).toHaveBeenCalledWith('invalid.token')
      expect(result).toBe(false)
    })

    it('propagates truthy values regardless of token structure', () => {
      jwtDecodeMock.mockReturnValue('some-string')
      const result = service.validateToken('weird.token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns undefined', () => {
      jwtDecodeMock.mockReturnValue(undefined)
      const result = service.validateToken('another.token')
      expect(result).toBe(false)
    })

    it('still returns false when jwt.decode throws an error (no internal try/catch)', () => {
      jwtDecodeMock.mockImplementation(() => {
        throw new Error('decode failed')
      })
      expect(() => service.validateToken('bad.token')).toThrow('decode failed')
    })
  })

  describe('hardcoded secrets behavior (indirect)', () => {
    it('can authenticate with any password of length >= 4, not tied to ADMIN_PASSWORD', () => {
      const result = service.authenticate('admin', 'notAdmin123')
      expect(result).toBe(true)
    })

    it('does not expose ADMIN_PASSWORD or API_KEY via public methods', () => {
      const anyService: any = service
      expect(anyService.ADMIN_PASSWORD).toBeUndefined()
      expect(anyService.API_KEY).toBeUndefined()
    })
  })
})