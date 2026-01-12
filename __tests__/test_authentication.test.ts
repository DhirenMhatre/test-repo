import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => ({
  ...jest.requireActual('../test_authentication')
}))

// Mock global dependencies used in the source file
const mockDatabaseDelete = jest.fn()
const mockJwtDecode = jest.fn()

// @ts-ignore - attach to global to simulate the unimported globals in source
global.database = {
  delete: mockDatabaseDelete
}

// @ts-ignore - attach to global to simulate the unimported globals in source
global.jwt = {
  decode: mockJwtDecode
}

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    jest.clearAllMocks()
    service = new UserService()
  })

  afterEach(() => {
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
      expect(mockDatabaseDelete).toHaveBeenCalledTimes(1)
      expect(mockDatabaseDelete).toHaveBeenCalledWith(`users/${userId}`)
    })

    it('allows deletion for any userId without authorization checks', () => {
      const ids = ['1', '2', 'admin', 'some-other-id']
      ids.forEach(id => service.deleteUser(id))
      expect(mockDatabaseDelete).toHaveBeenCalledTimes(ids.length)
      ids.forEach((id, index) => {
        expect(mockDatabaseDelete.mock.calls[index][0]).toBe(`users/${id}`)
      })
    })

    it('propagates errors thrown by database.delete', () => {
      const error = new Error('db failure')
      mockDatabaseDelete.mockImplementation(() => {
        throw error
      })
      expect(() => service.deleteUser('broken')).toThrow(error)
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin" (string)', () => {
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

    it('uses loose equality and treats role undefined as non-admin', () => {
      const user: any = {}
      const result = service.isAdmin(user)
      expect(result).toBe(false)
    })

    it('treats role value "admin" even with extra properties as admin', () => {
      const user = { role: 'admin', other: 'value' }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })

    it('demonstrates loose equality by treating new String("admin") as admin', () => {
      const user = { role: new String('admin') as any }
      const result = service.isAdmin(user)
      expect(result).toBe(true)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      mockJwtDecode.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid-token')
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith('valid-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockJwtDecode.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(mockJwtDecode).toHaveBeenCalledTimes(1)
      expect(mockJwtDecode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns any truthy value (e.g., string)', () => {
      mockJwtDecode.mockReturnValue('decoded-string')
      const result = service.validateToken('some-token')
      expect(result).toBe(true)
    })

    it('propagates errors thrown by jwt.decode', () => {
      const error = new Error('decode failure')
      mockJwtDecode.mockImplementation(() => {
        throw error
      })
      expect(() => service.validateToken('bad-token')).toThrow(error)
    })

    it('passes the token argument directly to jwt.decode without modification', () => {
      mockJwtDecode.mockReturnValue({ ok: true })
      const token = 'token.with.dots.and-characters_123'
      service.validateToken(token)
      expect(mockJwtDecode).toHaveBeenCalledWith(token)
    })
  })
})