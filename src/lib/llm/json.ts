import { writeFileSync } from "fs";
import { join } from "path";
import { PATHS } from "../../config/defaults.js";

export function extractJSON<T = any>(response: string, debugName?: string): T {
  let text = response.trim();
  text = text.replace(/```json\n?/g, "").replace(/```\n?/g, "");

  const firstBrace = text.indexOf("{");
  if (firstBrace === -1) {
    throw new Error(`No JSON found in response${debugName ? ` (${debugName})` : ""}`);
  }

  let depth = 0;
  let jsonEnd = firstBrace;
  for (let i = firstBrace; i < text.length; i++) {
    if (text[i] === "{") depth++;
    if (text[i] === "}") {
      depth--;
      if (depth === 0) {
        jsonEnd = i + 1;
        break;
      }
    }
  }

  const jsonStr = text.substring(firstBrace, jsonEnd);
  try {
    return JSON.parse(jsonStr);
  } catch {
    try {
      return JSON.parse(jsonStr.replace(/"([^"]*?)"\s*\([^)]+\)/g, '"$1"'));
    } catch {}

    try {
      return JSON.parse(jsonStr.replace(/,(\s*[}\]])/g, "$1"));
    } catch {}

    try {
      let cleaned = jsonStr.replace(/"([^"]*?)"\s*\([^)]+\)/g, '"$1"');
      cleaned = cleaned.replace(/,(\s*[}\]])/g, "$1");
      return JSON.parse(cleaned);
    } catch {}

    const debugPath = join(PATHS.BASE, `debug_${debugName || "malformed"}.json`);
    writeFileSync(debugPath, jsonStr, "utf-8");
    throw new Error(`JSON parse failed${debugName ? ` for ${debugName}` : ""}`);
  }
}
