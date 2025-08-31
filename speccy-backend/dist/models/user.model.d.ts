import { User } from '../types';
export declare class UserModel {
    private static findByTokenHashStmt;
    private static createStmt;
    private static updateLastSeenStmt;
    private static findByIdStmt;
    static hashToken(token: string): string;
    static findOrCreateByToken(openaiToken: string): Promise<User>;
    static findById(userId: string): Promise<User | null>;
    static updateLastSeen(userId: string): Promise<void>;
}
//# sourceMappingURL=user.model.d.ts.map