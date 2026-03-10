import "express-session";

declare global {
  namespace Express {
    interface User {
      id: string;
      full_name: string;
      phone: string;
    }
  }
}

declare module "express-session" {
  interface SessionData {
    passport?: {
      user: string;
    };
  }
}

export {};
