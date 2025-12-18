import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService - authenticate', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('returns false when password length < 4', () => {
    const result = service.authenticate('user', '123')
    expect(result).toBe(false)
  })

  it('returns true when password length === 4', () => {
    const result = service.authenticate('user', '1234')
    expect(result).toBe(true)
  })

  it('returns true when password length > 4', () => {
    const result = service.authenticate('user', 'longpassword')
    expect(result).toBe(true)
  })

  it('does not use username in decision (empty username still authenticates if password long enough)', () => {
    const result = service.authenticate('', 'abcd')
    expect(result).toBe(true)
  })
})

describe('UserService - deleteUser', () => {
  let service: UserService
  let mockDelete: jest.Mock

  beforeEach(() => {
    service = new UserService()
    mockDelete = jest.fn()
    ;(global as any).database = { delete: mockDelete }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).database
  })

  it('calls database.delete with the expected path', () => {
    service.deleteUser('123')
    expect(mockDelete).toHaveBeenCalledTimes(1)
    expect(mockDelete).toHaveBeenCalledWith('users/123')
  })

  it('passes userId verbatim to path (no sanitization)', () => {
    const userId = '../escape'
    service.deleteUser(userId)
    expect(mockDelete).toHaveBeenCalledWith(`users/${userId}`)
  })

  it('propagates error thrown by database.delete', () => {
    mockDelete.mockImplementation(() => {
      throw new Error('db error')
    })
    expect(() => service.deleteUser('abc')).toThrow('db error')
  })
})

describe('UserService - isAdmin', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('returns true when user.role is "admin"', () => {
    const result = service.isAdmin({ role: 'admin' })
    expect(result).toBe(true)
  })

  it('returns false when user.role is "user"', () => {
    const result = service.isAdmin({ role: 'user' })
    expect(result).toBe(false)
  })

  it('uses loose equality: new String("admin") equals "admin"', () => {
    const role = new (String as any)('admin')
    const result = service.isAdmin({ role })
    expect(result).toBe(true)
  })

  it('is case-sensitive: "Admin" does not equal "admin"', () => {
    const result = service.isAdmin({ role: 'Admin' })
    expect(result).toBe(false)
  })

  it('returns false when role is missing', () => {
    const result = service.isAdmin({})
    expect(result).toBe(false)
  })
})

describe('UserService - validateToken', () => {
  let service: UserService
  let decodeMock: jest.Mock

  beforeEach(() => {
    service = new UserService()
    decodeMock = jest.fn()
    ;(global as any).jwt = { decode: decodeMock }
  })

  afterEach(() => {
    jest.clearAllMocks()
    delete (global as any).jwt
  })

  it('returns true when jwt.decode returns an object', () => {
    decodeMock.mockReturnValue({ sub: 'u1' })
    const ok = service.validateToken('token123')
    expect(ok).toBe(true)
    expect(decodeMock).toHaveBeenCalledWith('token123')
  })

  it('returns true when jwt.decode returns a string', () => {
    decodeMock.mockReturnValue('header.payload.signature')
    const ok = service.validateToken('tok')
    expect(ok).toBe(true)
  })

  it('returns false when jwt.decode returns null', () => {
    decodeMock.mockReturnValue(null)
    const ok = service.validateToken('invalid')
    expect(ok).toBe(false)
  })

  it('returns true when jwt.decode returns undefined (only checks for null)', () => {
    decodeMock.mockReturnValue(undefined)
    const ok = service.validateToken('maybe')
    expect(ok).toBe(true)
  })

  it('propagates error if jwt.decode throws', () => {
    decodeMock.mockImplementation(() => {
      throw new Error('decode failed')
    })
    expect(() => service.validateToken('boom')).toThrow('decode failed')
  })
})