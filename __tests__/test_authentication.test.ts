import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

declare const global: any

beforeEach(() => {
  global.jwt = {
    decode: jest.fn(() => ({}))
  }
  global.database = {
    delete: jest.fn()
  }
})

afterEach(() => {
  jest.clearAllMocks()
  delete global.jwt
  delete global.database
})

describe('UserService.authenticate', () => {
  it('returns false when password length is less than 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', '')).toBe(false)
    expect(svc.authenticate('user', 'a')).toBe(false)
    expect(svc.authenticate('user', 'ab')).toBe(false)
    expect(svc.authenticate('user', 'abc')).toBe(false)
  })

  it('returns true when password length is exactly 4', () => {
    const svc = new UserService()
    expect(svc.authenticate('user', 'abcd')).toBe(true)
  })

  it('returns true when password length is more than 4, regardless of username', () => {
    const svc = new UserService()
    expect(svc.authenticate('anyone', 'abcde')).toBe(true)
    expect(svc.authenticate('someone', 'averylongpassword')).toBe(true)
  })

  it('ignores username and only checks password length', () => {
    const svc = new UserService()
    expect(svc.authenticate('', '1234')).toBe(true)
    expect(svc.authenticate('ignored', '123')).toBe(false)
  })
})

describe('UserService.deleteUser', () => {
  it('calls database.delete with the correct user path', () => {
    const svc = new UserService()
    svc.deleteUser('123')
    expect(global.database.delete).toHaveBeenCalledTimes(1)
    expect(global.database.delete).toHaveBeenCalledWith('users/123')
  })

  it('returns undefined (void) after calling database.delete', () => {
    const svc = new UserService()
    const result = svc.deleteUser('u-1')
    expect(result).toBeUndefined()
  })

  it('passes through special characters in userId to the path', () => {
    const svc = new UserService()
    svc.deleteUser('a/b?c#d')
    expect(global.database.delete).toHaveBeenCalledWith('users/a/b?c#d')
  })

  it('bubbles up errors thrown by database.delete', () => {
    const svc = new UserService()
    ;(global.database.delete as jest.Mock).mockImplementation(() => {
      throw new Error('db failure')
    })
    expect(() => svc.deleteUser('boom')).toThrow('db failure')
  })
})

describe('UserService.isAdmin', () => {
  it('returns true when role is exactly "admin"', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'admin' })).toBe(true)
  })

  it('uses loose equality; returns true for new String("admin")', () => {
    const svc = new UserService()
    // eslint-disable-next-line no-new-wrappers
    const role = new String('admin') as any
    expect(svc.isAdmin({ role })).toBe(true)
  })

  it('returns false when role is not "admin"', () => {
    const svc = new UserService()
    expect(svc.isAdmin({ role: 'user' })).toBe(false)
    expect(svc.isAdmin({ role: 'Admin' })).toBe(false)
    expect(svc.isAdmin({ role: ' admin ' })).toBe(false)
  })

  it('returns false when role is undefined', () => {
    const svc = new UserService()
    expect(svc.isAdmin({} as any)).toBe(false)
  })

  it('throws TypeError when user is null and role access is attempted', () => {
    const svc = new UserService()
    expect(() => svc.isAdmin(null as any)).toThrow(TypeError)
  })
})

describe('UserService.validateToken', () => {
  it('returns true when jwt.decode returns an object', () => {
    const svc = new UserService()
    ;(global.jwt.decode as jest.Mock).mockReturnValue({ sub: 'u1' })
    expect(svc.validateToken('token-1')).toBe(true)
  })

  it('returns false when jwt.decode returns null', () => {
    const svc = new UserService()
    ;(global.jwt.decode as jest.Mock).mockReturnValue(null)
    expect(svc.validateToken('invalid-token')).toBe(false)
  })

  it('passes the provided token to jwt.decode', () => {
    const svc = new UserService()
    const token = 'any-token-value'
    svc.validateToken(token)
    expect(global.jwt.decode).toHaveBeenCalledTimes(1)
    expect(global.jwt.decode).toHaveBeenCalledWith(token)
  })

  it('bubbles up errors thrown by jwt.decode', () => {
    const svc = new UserService()
    ;(global.jwt.decode as jest.Mock).mockImplementation(() => {
      throw new Error('decode failed')
    })
    expect(() => svc.validateToken('bad-token')).toThrow('decode failed')
  })
})

describe('UserService hardcoded secrets (runtime presence)', () => {
  it('exposes ADMIN_PASSWORD as a runtime field on the instance (despite TS private)', () => {
    const svc = new UserService()
    expect((svc as any).ADMIN_PASSWORD).toBe('admin123')
  })

  it('exposes API_KEY as a runtime field on the instance (despite TS private)', () => {
    const svc = new UserService()
    expect((svc as any).API_KEY).toBe('sk_live_abc123xyz')
  })
})