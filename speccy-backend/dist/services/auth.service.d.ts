import { User } from '../types';
export declare class AuthService {
    /**
     * Verify OpenAI API token by making a test request
     */
    static verifyOpenAIToken(token: string): Promise<boolean>;
    /**
     * Authenticate user with OpenAI token
     * Creates user if they don't exist, updates last_seen if they do
     */
    static authenticateWithOpenAI(openaiToken: string): Promise<User | null>;
    /**
     * Validate user exists and update last seen
     */
    static validateUser(userId: string): Promise<User | null>;
}
//# sourceMappingURL=auth.service.d.ts.map