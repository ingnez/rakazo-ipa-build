import { MessageBlock as MessageBlockSchema, type MessageBlock } from "@rakazo/contracts";

/**
 * Persisted blocks are JSON and older writers (or offline fixtures) can omit fields the
 * current contract requires — notably `mimeType` on `image` / `file`. oRPC then rejects the
 * whole `threads/get` output ("Output validation failed") and the chat goes blank.
 *
 * Repair what we can; drop a block only when it still cannot satisfy the contract. Never throw.
 */
export function sanitizeMessageBlocksForClient(blocks: unknown): MessageBlock[] {
  if (!Array.isArray(blocks)) return [];
  const out: MessageBlock[] = [];
  for (const raw of blocks) {
    const repaired = repairMessageBlock(raw);
    if (repaired) out.push(repaired);
  }
  return out;
}

function repairMessageBlock(raw: unknown): MessageBlock | undefined {
  const first = MessageBlockSchema.safeParse(raw);
  if (first.success) return first.data;
  if (!raw || typeof raw !== "object") return undefined;
  const block = raw as Record<string, unknown>;
  const kind = block.kind;
  if (kind === "image") {
    const name = typeof block.name === "string" ? block.name : "image";
    const candidate = {
      ...block,
      name,
      mimeType:
        typeof block.mimeType === "string" && block.mimeType.trim()
          ? block.mimeType
          : mimeFromName(name, "image/png"),
    };
    const parsed = MessageBlockSchema.safeParse(candidate);
    return parsed.success ? parsed.data : undefined;
  }
  if (kind === "file") {
    const name = typeof block.name === "string" ? block.name : "file";
    const candidate = {
      ...block,
      name,
      mimeType:
        typeof block.mimeType === "string" && block.mimeType.trim()
          ? block.mimeType
          : mimeFromName(name, "application/octet-stream"),
      size:
        typeof block.size === "number" && Number.isFinite(block.size) && block.size >= 0
          ? block.size
          : 0,
    };
    const parsed = MessageBlockSchema.safeParse(candidate);
    return parsed.success ? parsed.data : undefined;
  }
  return undefined;
}

function mimeFromName(name: string, fallback: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".txt")) return "text/plain";
  if (lower.endsWith(".md")) return "text/markdown";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".zip")) return "application/zip";
  return fallback;
}
