import { OpenAI } from 'openai';
import { UserModel } from '../models/user.model';
import { User } from '../types';

export class AuthService {
  /**
   * Verify OpenAI API token by making a test request
   */
  static async verifyOpenAIToken(token: string): Promise<boolean> {
    try {
      const openai = new OpenAI({ apiKey: token });
      
      // Make a simple API call to verify the token
      // We'll use the models endpoint as it's lightweight
      await openai.models.list();
      
      return true;
    } catch (error: any) {
      console.log('OpenAI token verification failed:', error.message);
      return false;
    }
  }

  /**
   * Authenticate user with OpenAI token
   * Creates user if they don't exist, updates last_seen if they do
   */
  static async authenticateWithOpenAI(openaiToken: string): Promise<User | null> {
    // First verify the token is valid
    const isValidToken = await this.verifyOpenAIToken(openaiToken);
    if (!isValidToken) {
      return null;
    }

    // Find or create user
    const user = await UserModel.findOrCreateByToken(openaiToken);
    return user;
  }

  /**
   * Validate user exists and update last seen
   */
  static async validateUser(userId: string): Promise<User | null> {
    const user = await UserModel.findById(userId);
    if (user) {
      await UserModel.updateLastSeen(userId);
    }
    return user;
  }
}