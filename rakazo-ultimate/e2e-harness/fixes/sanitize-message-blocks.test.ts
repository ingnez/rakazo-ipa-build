import { MessageBlock, ThreadMessageSchema } from "@rakazo/contracts";
import { describe, expect, it } from "vitest";
import { sanitizeMessageBlocksForClient } from "./sanitize-message-blocks.js";

describe("sanitizeMessageBlocksForClient", () => {
  it("fills mimeType on image blocks that omitted it (keeps the picture)", () => {
    const blocks = sanitizeMessageBlocksForClient([
      { kind: "text", text: "Fixture picture stack" },
      { kind: "image", artifactId: "img-1", name: "stack-1.png" },
      { kind: "image", artifactId: "img-2", name: "stack-2.png" },
    ]);
    expect(blocks).toHaveLength(3);
    expect(blocks[1]).toMatchObject({
      kind: "image",
      artifactId: "img-1",
      mimeType: "image/png",
    });
    expect(blocks[2]).toMatchObject({ kind: "image", mimeType: "image/png" });
    expect(() => MessageBlock.array().parse(blocks)).not.toThrow();
  });

  it("fills mimeType and size on file blocks that omitted them", () => {
    const blocks = sanitizeMessageBlocksForClient([
      { kind: "file", artifactId: "file-1", name: "notes.txt" },
    ]);
    expect(blocks).toEqual([
      {
        kind: "file",
        artifactId: "file-1",
        name: "notes.txt",
        mimeType: "text/plain",
        size: 0,
      },
    ]);
    expect(() => MessageBlock.array().parse(blocks)).not.toThrow();
  });

  it("keeps a thread message contract-valid when only the attachment fields were missing", () => {
    const message = {
      id: "msg-1",
      threadId: "thread-1",
      seq: 5,
      role: "bot" as const,
      blocks: sanitizeMessageBlocksForClient([
        { kind: "text", text: "The fixture workspace is ready." },
        { kind: "image", artifactId: "img-1", name: "stack-1.png" },
        { kind: "file", artifactId: "file-1", name: "launch-notes.txt" },
      ]),
      createdAt: new Date().toISOString(),
    };
    expect(() => ThreadMessageSchema.parse(message)).not.toThrow();
  });

  it("drops blocks that are not repairable, without throwing", () => {
    const blocks = sanitizeMessageBlocksForClient([
      { kind: "image" }, // no artifactId
      { kind: "not-a-real-kind", text: "x" },
      null,
      { kind: "text", text: "kept" },
    ]);
    expect(blocks).toEqual([{ kind: "text", text: "kept" }]);
  });
});
