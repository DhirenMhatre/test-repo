import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  return {
    ...actual
  }
})

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: jest.fn()
}))

const mockedJwt = jest.requireMock('jwt') as { decode: jest.Mock }

declare const database: { delete: (path: string) => void }

jest.mock('../test_authentication_database_dep', () => {
  const deleteFn = jest.fn()
  ;(global as any).database = { delete: deleteFn }
  return {
    delete: deleteFn
  }
})

describe('UserService', () => {
  let service: UserService
  let deleteSpy: jest.SpyInstance

  beforeEach(() => {
    service = new UserService()
    deleteSpy = jest.spyOn((global as any).database, 'delete')
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
      service.deleteUser('123')
      expect(deleteSpy).toHaveBeenCalledTimes(1)
      expect(deleteSpy).toHaveBeenCalledWith('users/123')
    })

    it('allows deleting user with arbitrary string id', () => {
      service.deleteUser('some-random-id')
      expect(deleteSpy).toHaveBeenCalledWith('users/some-random-id')
    })

    it('does not perform any authorization checks before deleting', () => {
      service.deleteUser('no-auth-check')
      expect(deleteSpy).toHaveBeenCalledTimes(1)
    })

    it('propagates database.delete being called multiple times for different users', () => {
      service.deleteUser('1')
      service.deleteUser('2')
      service.deleteUser('3')
      expect(deleteSpy).toHaveBeenCalledTimes(3)
      expect(deleteSpy).toHaveBeenNthCalledWith(1, 'users/1')
      expect(deleteSpy).toHaveBeenNthCalledWith(2, 'users/2')
      expect(deleteSpy).toHaveBeenNthCalledWith(3, 'users/3')
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

    it('uses loose equality so numeric 0 compared to "admin" is false', () => {
      const result = service.isAdmin({ role: 0 })
      expect(result).toBe(false)
    })

    it('treats string "0" as non-admin', () => {
      const result = service.isAdmin({ role: '0' })
      expect(result).toBe(false)
    })

    it('returns false when user object has no role property', () => {
      const result = service.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when user is null or undefined-like object', () => {
      const result = service.isAdmin({ role: null })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('returns true when jwt.decode returns a non-null value', () => {
      mockedJwt.decode.mockReturnValue({ sub: '123' })
      const result = service.validateToken('valid-token')
      expect(mockedJwt.decode).toHaveBeenCalledTimes(1)
      expect(mockedJwt.decode).toHaveBeenCalledWith('valid-token')
      expect(result).toBe(true)
    })

    it('returns false when jwt.decode returns null', () => {
      mockedJwt.decode.mockReturnValue(null)
      const result = service.validateToken('invalid-token')
      expect(mockedJwt.decode).toHaveBeenCalledTimes(1)
      expect(mockedJwt.decode).toHaveBeenCalledWith('invalid-token')
      expect(result).toBe(false)
    })

    it('returns true when jwt.decode returns an empty object', () => {
      mockedJwt.decode.mockReturnValue({})
      const result = service.validateToken('empty-payload-token')
      expect(result).toBe(true)
    })

    it('propagates multiple calls to jwt.decode for different tokens', () => {
      mockedJwt.decode
        .mockReturnValueOnce({ sub: '1' })
        .mockReturnValueOnce(null)
        .mockReturnValueOnce({ sub: '3' })

      const result1 = service.validateToken('token-1')
      const result2 = service.validateToken('token-2')
      const result3 = service.validateToken('token-3')

      expect(result1).toBe(true)
      expect(result2).toBe(false)
      expect(result3).toBe(true)
      expect(mockedJwt.decode).toHaveBeenCalledTimes(3)
      expect(mockedJwt.decode).toHaveBeenNthCalledWith(1, 'token-1')
      expect(mockedJwt.decode).toHaveBeenNthCalledWith(2, 'token-2')
      expect(mockedJwt.decode).toHaveBeenNthCalledWith(3, 'token-3')
    })

    it('does not perform any expiration validation on decoded token', () => {
      const decodedPayload = { sub: '123', exp: 0 }
      mockedJwt.decode.mockReturnValue(decodedPayload)
      const result = service.validateToken('expired-token')
      expect(result).toBe(true)
    })
  })
})