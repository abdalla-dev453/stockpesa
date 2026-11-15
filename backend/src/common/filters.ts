import { ArgumentsHost, Catch, ExceptionFilter } from "@nestjs/common";
import { Prisma } from "@prisma/client";
@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaFilter implements ExceptionFilter {
  catch(e: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost) {
    const map: any = {
      P2002: [409, "This value is already in use"],
      P2025: [404, "Record not found"],
      P2003: [422, "A referenced record does not exist"],
    };
    const [statusCode, message] = map[e.code] ?? [
      500,
      "Unexpected server error",
    ];
    host
      .switchToHttp()
      .getResponse()
      .status(statusCode)
      .json({ statusCode, message });
  }
}
