import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let service: UserService

  beforeEach(() => {
    service = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('creates an instance', () => {
    expect(service).toBeInstanceOf(UserService)
  })

  it('exposes runtime property ADMIN_PASSWORD (hardcoded secret present at runtime)', () => {
    expect((service as any).ADMIN_PASSWORD).toBe('admin123')
  })

  it('exposes runtime property API_KEY (hardcoded secret present at runtime)', () => {
    expect((service as any).API_KEY).toBe('sk_live_abc123xyz')
  })

  it.each([0, 1, 2, 3])('authenticate returns false for password length %i (<4)', (n) => {
    const result = service.authenticate('any-user', 'a'.repeat(n))
    expect(result).toBe(false)
  })

  it.each([4, 5, 10, 50])('authenticate returns true for password length %i (>=4)', (n) => {
    const result = service.authenticate('any-user', 'a'.repeat(n))
    expect(result).toBe(true)
  })

  it('authenticate ignores username and only checks password length', () => {
    const pass = 'abcd' // length 4 -> true
    const r1 = service.authenticate('user-one', pass)
    const r2 = service.authenticate('different-user', pass)
    expect(r1).toBe(true)
    expect(r2).toBe(true)
  })

  it('authenticate returns a boolean', () => {
    const result = service.authenticate('u', 'abcd')
    expect(typeof result).toBe('boolean')
  })

  it('isAdmin returns true when role is exactly "admin"', () => {
    expect(service.isAdmin({ role: 'admin' })).toBe(true)
  })

  it('isAdmin returns false when role is "user"', () => {
    expect(service.isAdmin({ role: 'user' })).toBe(false)
  })

  it('isAdmin performs loose equality: true for new String("admin")', () => {
    // new String('admin') is an object, but == "admin" coerces to true
    const roleObj = new String('admin') as any
    expect(service.isAdmin({ role: roleObj })).toBe(true)
  })

  it('isAdmin can coerce objects with toString() returning "admin" to true (due to ==)', () => {
    const trickyRole = {
      toString: () => 'admin',
      valueOf: () => 0
    }
    expect(service.isAdmin({ role: trickyRole as any })).toBe(true)
  })

  it('isAdmin returns false for uppercase "ADMIN"', () => {
    expect(service.isAdmin({ role: 'ADMIN' })).toBe(false)
  })

  it('isAdmin returns false when role is missing', () => {
    expect(service.isAdmin({} as any)).toBe(false)
  })

  it('isAdmin returns false when role has extra whitespace', () => {
    expect(service.isAdmin({ role: ' admin' })).toBe(false)
    expect(service.isAdmin({ role: 'admin ' })).toBe(false)
    expect(service.isAdmin({ role: ' admin ' })).toBe(false)
  })

  it('isAdmin throws when user is null (cannot read role)', () => {
    expect(() => service.isAdmin(null as any)).toThrow(TypeError)
  })

  it('validateToken throws ReferenceError when jwt is not defined', () => {
    expect(() => service.validateToken('any-token')).toThrow(ReferenceError)
  })

  it('validateToken error message mentions jwt', () => {
    try {
      service.validateToken('any-token')
      throw new Error('expected to throw')
    } catch (err: any) {
      expect(String(err)).toMatch(/jwt/i)
    }
  })

  it('deleteUser throws ReferenceError when database is not defined', () => {
    expect(() => service.deleteUser('user-123')).toThrow(ReferenceError)
  })

  it('deleteUser error message mentions database', () => {
    try {
      service.deleteUser('user-123')
      throw new Error('expected to throw')
    } catch (err: any) {
      expect(String(err)).toMatch(/database/i)
    }
  })
})