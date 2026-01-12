import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

const mockDelete = jest.fn()
const mockJwtDecode = jest.fn()

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  return {
    ...actual
  }
})

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: (...args: any[]) => mockJwtDecode(...args)
}))

// Provide a global database object as used in the source file
;(global as any).database = {
  delete: (...args: any[]) => mockDelete(...args)
}

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
    mockDelete.mockReset()
    mockJwtDecode.mockReset()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password length is less than 4 (empty password)', () => {
      const result = service.authenticate('user', '')
      expect(result).toBe(false)
    })

    it('returns false when password length is less than 4 (short password)', () => {
      const result = service.authenticate('user', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = service.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('returns true when password length is greater than 4', () => {
      const result = service.authenticate('user', 'longpassword')
      expect(result).toBe(true)
    })

    it('ignores username and only checks password length', () => {
      const result1 = service.authenticate('user1', 'abcd')
      const result2 = service.authenticate('user2', 'abcd')
      expect(result1).toBe(true)
      expect(result2).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('calls database.delete with the correct user path', () => {
      const userId = '123'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledTimes(1)
      expect(mockDelete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('allows deletion of user with empty string id', () => {
      const userId = ''
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledWith('users/')
    })

    it('allows deletion of user with special characters in id', () => {
      const userId = 'abc/../def'
      service.deleteUser(userId)
      expect(mockDelete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('propagates errors thrown by database.delete', () => {
      const error = new Error('delete failed')
      mockDelete.mockImplementation(() => {
        throw error
      })
      expect(() => service.deleteUser('123')).toThrow(error)
    })
  })

  describe('isAdmin', () => {
    it('returns true when user.role is the string "admin"', () => {
      const user = { role: 'admin' }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('returns false when user.role is not "admin"', () => {
      const user = { role: 'user' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats number 0 as not admin', () => {
      const user = { role: 0 }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats string "0" as not admin', () => {
      const user = { role: '0' }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('uses loose equality and treats boolean true as not admin', () => {
      const user = { role: true }
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user has no role property', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('returns false when user is null', () => {
      const user: any = null
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      const decodedValue = { sub: '123' }
      mockJwtDecode.mockReturnValue(decodedValue)
      const result = service.validateToken('valid.token.here')
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith('valid.token.here')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = service.validateToken('invalid.token')
      expect(mockJwtDecode).toHaveBeenCalledWith('invalid.token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns an empty object', () => {
      mockJwtDecode.mockReturnValue({})
      const result = service.validateToken('token.with.empty.payload')
      expect(result).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const error = new Error('decode failed')
      mockJwtDecode.mockImplementation(() => {
        throw error
      })
      expect(() => service.validateToken('bad.token')).toThrow(error)
    })

    it('passes the token string directly to jwt.decode without modification', () => {
      mockJwtDecode.mockReturnValue({ ok: true })
      const token = 'raw.token.string'
      service.validateToken(token)
      expect(mockJwtDecode).toHaveBeenCalledWith(token)
    })
  })
})