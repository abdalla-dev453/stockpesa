import {
  CanActivate,
  ExecutionContext,
  Injectable,
  SetMetadata,
  UnauthorizedException,
  ForbiddenException,
  createParamDecorator,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { JwtService } from "@nestjs/jwt";
import { PrismaService } from "../prisma.service";
export const Roles = (...r: string[]) => SetMetadata("roles", r);
export const Me = createParamDecorator(
  (_d, ctx: ExecutionContext) => ctx.switchToHttp().getRequest().user,
);
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private jwt: JwtService,
    private ref: Reflector,
    private db: PrismaService,
  ) {}
  async canActivate(ctx: ExecutionContext) {
    const req = ctx.switchToHttp().getRequest();
    const tok = (req.headers.authorization || "").replace("Bearer ", "");
    let claims: any;
    try {
      claims = this.jwt.verify(tok, { secret: process.env.JWT_ACCESS_SECRET });
    } catch {
      throw new UnauthorizedException("Invalid or expired token");
    }
    const activeUser = await this.db.user.findFirst({ where: { id: claims.sub, businessId: claims.businessId, deletedAt: null }, select: { role: true } });
    if (!activeUser) throw new UnauthorizedException("Account is inactive or no longer exists");
    req.user = { ...claims, role: activeUser.role };
    const roles = this.ref.get<string[]>("roles", ctx.getHandler());
    if (roles?.length && !roles.includes(req.user.role))
      throw new ForbiddenException("Your role cannot do this");
    return true; // req.user = { sub, businessId, role }
  }
}
