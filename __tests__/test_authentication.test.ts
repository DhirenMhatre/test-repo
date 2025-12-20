import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { UserService } from '../test_authentication'

describe('UserService', () => {
  let svc: UserService

  beforeEach(() => {
    svc = new UserService()
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('authenticate', () => {
    it('returns false when password is shorter than 4 characters', () => {
      const result = svc.authenticate('anyuser', 'abc')
      expect(result).toBe(false)
    })

    it('returns true when password length is exactly 4', () => {
      const result = svc.authenticate('user', 'abcd')
      expect(result).toBe(true)
    })

    it('ignores username and returns true for sufficiently long password even with empty username', () => {
      const result = svc.authenticate('', '1234')
      expect(result).toBe(true)
    })

    it('returns true for long passwords (no other checks)', () => {
      const result = svc.authenticate('someone', 'averylongpassword12345')
      expect(result).toBe(true)
    })
  })

  describe('deleteUser', () => {
    it('throws ReferenceError because "database" is not defined in module scope', () => {
      expect(() => svc.deleteUser('u1')).toThrow(ReferenceError)
    })

    it('error message mentions database is not defined', () => {
      try {
        svc.deleteUser('u2')
        // Should not reach here
        expect(true).toBe(false)
      } catch (e: any) {
        expect(String(e)).toMatch(/database is not defined/)
      }
    })
  })

  describe('isAdmin', () => {
    it('returns true when role is exactly "admin"', () => {
      const result = svc.isAdmin({ role: 'admin' })
      expect(result).toBe(true)
    })

    it('returns true when role is a String object "admin" due to loose equality', () => {
      // eslint-disable-next-line no-new-wrappers
      const roleObj = new String('admin') as unknown as string
      const result = svc.isAdmin({ role: roleObj })
      expect(result).toBe(true)
    })

    it('returns false when role is different casing ("ADMIN")', () => {
      const result = svc.isAdmin({ role: 'ADMIN' })
      expect(result).toBe(false)
    })

    it('returns false when role is missing', () => {
      const result = svc.isAdmin({})
      expect(result).toBe(false)
    })

    it('returns false when role is a non-string type', () => {
      const result = svc.isAdmin({ role: 0 as unknown as string })
      expect(result).toBe(false)
    })
  })

  describe('validateToken', () => {
    it('throws ReferenceError because "jwt" is not defined in module scope', () => {
      expect(() => svc.validateToken('any.token.value')).toThrow(ReferenceError)
    })

    it('error message mentions jwt is not defined', () => {
      try {
        svc.validateToken('another.token')
        expect(true).toBe(false)
      } catch (e: any) {
        expect(String(e)).toMatch(/jwt is not defined/)
      }
    })
  })

  describe('hardcoded secrets presence and mutability', () => {
    it('exposes ADMIN_PASSWORD at runtime with expected value', () => {
      const adminPass = (svc as any).ADMIN_PASSWORD
      expect(adminPass).toBe('admin123')
    })

    it('exposes API_KEY at runtime with expected value', () => {
      const apiKey = (svc as any).API_KEY
      expect(apiKey).toBe('sk_live_abc123xyz')
    })

    it('allows mutating ADMIN_PASSWORD despite readonly at compile time', () => {
      const localSvc = new UserService()
      expect((localSvc as any).ADMIN_PASSWORD).toBe('admin123')
      ;(localSvc as any).ADMIN_PASSWORD = 'changed'
      expect((localSvc as any).ADMIN_PASSWORD).toBe('changed')
    })

    it('allows mutating API_KEY despite readonly at compile time', () => {
      const localSvc = new UserService()
      expect((localSvc as any).API_KEY).toBe('sk_live_abc123xyz')
      ;(localSvc as any).API_KEY = 'new_key_456'
      expect((localSvc as any).API_KEY).toBe('new_key_456')
    })

    it('hardcoded fields are enumerable on the instance', () => {
      const keys = Object.keys(svc as any)
      expect(keys).toEqual(expect.arrayContaining(['ADMIN_PASSWORD', 'API_KEY']))
    })
  })
})