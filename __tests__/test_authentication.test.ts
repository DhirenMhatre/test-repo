import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService - authenticate', () => {
  it('returns false when password is empty', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', '')).toBe(false)
  })

  it('returns false when password length is less than 4 (e.g., length 3)', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', '123')).toBe(false)
  })

  it('returns true when password length is exactly 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', '1234')).toBe(true)
  })

  it('returns true when password length is greater than or equal to 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', 'longpassword')).toBe(true)
  })

  it('ignores username and bases decision solely on password length', () => {
    const svc = new UserService()
    expect(svc.authenticate('someone', 'abcd')).toBe(true)
    expect(svc.authenticate('differentUser', 'abc')).toBe(false)
  })

  it('treats any 4+ length password as valid regardless of content', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', '    ')).toBe(true)
    expect(svc.authenticate('user', 'pass')).toBe(true)
  })
})

describe('UserService - deleteUser', () => {
  let originalDatabase: any
  let mockDelete: jest.Mock

  beforeEach(() => {
    originalDatabase = (globalThis as any).database
    mockDelete = jest.fn()
    ;(globalThis as any).database = { delete: mockDelete }
  })

  afterEach(() => {
    ;(globalThis as any).database = originalDatabase
  })

  it('calls database.delete with the correct user path', () => {
    const svc = new UserService()
    svc.deleteUser('u123')
    expect(mockDelete).toHaveBeenCalledTimes(1)
    expect(mockDelete).toHaveBeenCalledWith('users/u123')
  })

  it('calls database.delete with different userIds correctly', () => {
    const svc = new UserService()
    svc.deleteUser('alpha')
    svc.deleteUser('beta')
    expect(mockDelete).toHaveBeenCalledTimes(2)
    expect(mockDelete).toHaveBeenNthCalledWith(1, 'users/alpha')
    expect(mockDelete).toHaveBeenNthCalledWith(2, 'users/beta')
  })

  it('propagates errors thrown by database.delete', () => {
    mockDelete.mockImplementation(() => {
      throw new Error('DB failure')
    })
    const svc = new UserService()
    expect(() => svc.deleteUser('boom')).toThrow('DB failure')
  })

  it('supports multiple consecutive deletions', () => {
    const svc = new UserService()
    const ids = ['1', '2', '3', '4']
    ids.forEach(id => svc.deleteUser(id))
    expect(mockDelete).toHaveBeenCalledTimes(ids.length)
    ids.forEach((id, idx) => {
      expect(mockDelete).toHaveBeenNthCalledWith(idx + 1, `users/${id}`)
    })
  })
})

describe('UserService - isAdmin (loose equality check)', () => {
  it('returns true when role is exactly "admin"', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'admin' })).toBe(true)
  })

  it('returns true when role is a String object containing "admin"', () => {
    const svc = new UserService()
    const stringObj = new String('admin') as any
    expect(svc.isAdmin({ role: stringObj })).toBe(true)
  })

  it('returns true when role object coerces to "admin" via toString', () => {
    const svc = new UserService()
    const roleObj = {
      toString: () => 'admin'
    }
    expect(svc.isAdmin({ role: roleObj as any })).toBe(true)
  })

  it('returns false for non-matching case "ADMIN"', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'ADMIN' })).toBe(false)
  })

  it('returns false for trailing spaces "admin "', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'admin ' })).toBe(false)
  })

  it('returns false when role is undefined or non-admin values', () => {
    const svc = new UserService()
    expect(svc.isAdmin({})).toBe(false)
    expect(svc.isAdmin({ role: undefined })).toBe(false)
    expect(svc.isAdmin({ role: null })).toBe(false)
    expect(svc.isAdmin({ role: 123 })).toBe(false)
    expect(svc.isAdmin({ role: false })).toBe(false)
    expect(svc.isAdmin({ role: 'user' })).toBe(false)
  })
})

describe('UserService - validateToken (uses jwt.decode without expiration checks)', () => {
  let originalJwt: any
  let mockDecode: jest.Mock

  beforeEach(() => {
    originalJwt = (globalThis as any).jwt
    mockDecode = jest.fn()
    ;(globalThis as any).jwt = { decode: mockDecode }
  })

  afterEach(() => {
    ;(globalThis as any).jwt = originalJwt
  })

  it('returns true when jwt.decode returns an object', () => {
    mockDecode.mockReturnValue({ sub: '123' })
    const svc = new UserService()
    expect(svc.validateToken('valid.token.here')).toBe(true)
  })

  it('returns false when jwt.decode returns null', () => {
    mockDecode.mockReturnValue(null)
    const svc = new UserService()
    expect(svc.validateToken('invalid.token')).toBe(false)
  })

  it('passes the token argument through to jwt.decode', () => {
    mockDecode.mockReturnValue({ foo: 'bar' })
    const svc = new UserService()
    const token = 'xyz.abc.123'
    svc.validateToken(token)
    expect(mockDecode).toHaveBeenCalledTimes(1)
    expect(mockDecode).toHaveBeenCalledWith(token)
  })

  it('returns true even if decoded token lacks exp or is "expired"', () => {
    mockDecode.mockReturnValue({ sub: '1', exp: 0 })
    const svc = new UserService()
    expect(svc.validateToken('expired.token')).toBe(true)
  })
})