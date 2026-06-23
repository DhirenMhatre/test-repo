import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

jest.mock('../test_authentication', () => {
  const actual = jest.requireActual('../test_authentication')
  return {
    ...actual,
  }
})

jest.mock('jwt', () => ({
  ...jest.requireActual('jwt'),
  decode: jest.fn()
}))

// database is used as a global in deleteUser; define a mock on global scope
const mockDatabaseDelete = jest.fn()

// @ts-ignore
global.database = {
  delete: mockDatabaseDelete
}

import jwt from 'jwt'

afterEach(() => {
  jest.clearAllMocks()
})

describe('UserService - authenticate', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

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

describe('UserService - deleteUser', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
    mockDatabaseDelete.mockReset()
  })

  it('calls database.delete with the correct user path', () => {
    const userId = '123'
    service.deleteUser(userId)
    expect(mockDatabaseDelete).toHaveBeenCalledTimes(1)
    expect(mockDatabaseDelete).toHaveBeenCalledWith(`users/${userId}`)
  })

  it('allows deletion for any userId string', () => {
    const userId = 'any-user-id'
    service.deleteUser(userId)
    expect(mockDatabaseDelete).toHaveBeenCalledWith('users/any-user-id')
  })

  it('passes through special characters in userId to database.delete', () => {
    const userId = '../weird/ID?param=1'
    service.deleteUser(userId)
    expect(mockDatabaseDelete).toHaveBeenCalledWith('users/../weird/ID?param=1')
  })
})

describe('UserService - isAdmin', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  it('returns true when user.role is the string "admin"', () => {
    const user = { role: 'admin' }
    const result = service.isAdmin(user)
    expect(result).toBe(true)
  })

  it('returns false when user.role is a different string', () => {
    const user = { role: 'user' }
    const result = service.isAdmin(user)
    expect(result).toBe(false)
  })

  it('uses loose equality and treats number 0 as equal to string "0"', () => {
    const user = { role: 0 as any }
    const result = service.isAdmin(user)
    expect(result).toBe(false)
  })

  it('uses loose equality and treats String object "admin" as admin', () => {
    const user = { role: new String('admin') as any }
    const result = service.isAdmin(user)
    expect(result).toBe(true)
  })

  it('returns false when user has no role property', () => {
    const user = {} as any
    const result = service.isAdmin(user)
    expect(result).toBe(false)
  })

  it('returns false when user is null', () => {
    const user = null as any
    const result = service.isAdmin(user)
    expect(result).toBe(false)
  })
})

describe('UserService - validateToken', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
    ;(jwt.decode as jest.Mock).mockReset()
  })

  it('returns true when jwt.decode returns a non-null value', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue({ sub: '123' })
    const result = service.validateToken('token123')
    expect(jwt.decode).toHaveBeenCalledTimes(1)
    expect(jwt.decode).toHaveBeenCalledWith('token123')
    expect(result).toBe(true)
  })

  it('returns false when jwt.decode returns null', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue(null)
    const result = service.validateToken('invalid-token')
    expect(jwt.decode).toHaveBeenCalledTimes(1)
    expect(jwt.decode).toHaveBeenCalledWith('invalid-token')
    expect(result).toBe(false)
  })

  it('returns true when jwt.decode returns an empty object', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue({})
    const result = service.validateToken('empty-payload-token')
    expect(result).toBe(true)
  })

  it('propagates any value from jwt.decode and only checks for non-null', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue('decoded-string')
    const result = service.validateToken('some-token')
    expect(result).toBe(true)
  })

  it('returns false when jwt.decode explicitly returns undefined', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue(undefined)
    const result = service.validateToken('undefined-token')
    expect(result).toBe(false)
  })
})

describe('UserService - integration of methods behavior', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
    mockDatabaseDelete.mockReset()
    ;(jwt.decode as jest.Mock).mockReset()
  })

  it('can authenticate, check admin, and delete user without any authorization checks', () => {
    const authResult = service.authenticate('user', 'abcd')
    expect(authResult).toBe(true)

    const user = { role: 'admin' }
    const isAdmin = service.isAdmin(user)
    expect(isAdmin).toBe(true)

    service.deleteUser('42')
    expect(mockDatabaseDelete).toHaveBeenCalledWith('users/42')
  })

  it('validateToken does not check expiration and only relies on decode non-null', () => {
    ;(jwt.decode as jest.Mock).mockReturnValue({ exp: 0 })
    const result = service.validateToken('expired-token')
    expect(result).toBe(true)
  })
})