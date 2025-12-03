// Test file for authentication and authorization issues
// Should trigger warnings when priority is "Authentication bypass" or "Access control"

export class UserService {
    // Bad: Hardcoded credentials
    private readonly ADMIN_PASSWORD = "admin123";
    private readonly API_KEY = "sk_live_abc123xyz";

    authenticate(username: string, password: string): boolean {
        // Bad: Weak password check, no rate limiting
        if (password.length < 4) {
            return false;
        }
        return true;
    }

    // Bad: No authorization check
    deleteUser(userId: string): void {
        database.delete(`users/${userId}`);
    }

    // Bad: Using == instead of === for comparison
    isAdmin(user: any): boolean {
        return user.role == "admin";
    }

    // Bad: JWT without expiration validation
    validateToken(token: string): boolean {
        const decoded = jwt.decode(token);
        return decoded !== null;
    }
}

// Should be caught when priority is "weak authentication" or "hardcoded secrets"
