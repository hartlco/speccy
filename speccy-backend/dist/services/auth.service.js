"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const openai_1 = require("openai");
const user_model_1 = require("../models/user.model");
class AuthService {
    /**
     * Verify OpenAI API token by making a test request
     */
    static async verifyOpenAIToken(token) {
        try {
            const openai = new openai_1.OpenAI({ apiKey: token });
            // Make a simple API call to verify the token
            // We'll use the models endpoint as it's lightweight
            await openai.models.list();
            return true;
        }
        catch (error) {
            console.log('OpenAI token verification failed:', error.message);
            return false;
        }
    }
    /**
     * Authenticate user with OpenAI token
     * Creates user if they don't exist, updates last_seen if they do
     */
    static async authenticateWithOpenAI(openaiToken) {
        // First verify the token is valid
        const isValidToken = await this.verifyOpenAIToken(openaiToken);
        if (!isValidToken) {
            return null;
        }
        // Find or create user
        const user = await user_model_1.UserModel.findOrCreateByToken(openaiToken);
        return user;
    }
    /**
     * Validate user exists and update last seen
     */
    static async validateUser(userId) {
        const user = await user_model_1.UserModel.findById(userId);
        if (user) {
            await user_model_1.UserModel.updateLastSeen(userId);
        }
        return user;
    }
}
exports.AuthService = AuthService;
//# sourceMappingURL=auth.service.js.map