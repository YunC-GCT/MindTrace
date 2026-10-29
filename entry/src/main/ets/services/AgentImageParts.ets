/**
 * AgentImageParts.ets — A2A 请求 part 的形状判定与图片提取（纯函数）
 *
 * 路径: entry/src/main/ets/services/AgentImageParts.ets
 * 职责: 把小艺请求里的 parts[] 归一成「文本 part / 图片 part」两种，图片供 OCR 节点使用
 * 依赖: 无（不碰 Context、不碰 Kit，可直接单测）
 *
 * 协议事实（API 26 实测）：文本 part 只有 { mediaType, text }；
 *   图片按 BCP 惯例会落在 { mediaType: 'image/*', raw: '<base64>' } 或 { url: 'file://…' }。
 *   当前小艺客户端还不下发图片 part，这里的提取逻辑先按契约写好，
 *   等平台透传后无需改调用方。
 */

/** A2A message.parts[] 的元素（proto-JSON 字段名，v1.0 无 kind 字段） */
export interface AgentPart {
  mediaType?: string;
  text?: string;
  raw?: string;
  url?: string;
  data?: string | number | boolean | object;
  filename?: string;
}

/** 一张待识别的图片：kind 决定用什么方式取字节 */
export interface AgentImagePart {
  /** 'base64' = part.raw 里直接是图片字节；'uri' = part.url 指向本地文件 */
  kind: string;
  value: string;
}

/** mediaType 以 image/ 开头即图片；缺失 mediaType 但有 raw 的按图片兜底 */
export function isImagePart(part: AgentPart): boolean {
  const mediaType: string = part.mediaType === undefined ? '' : part.mediaType;
  if (mediaType.indexOf('image/') === 0) {
    return true;
  }
  const raw: string = part.raw === undefined ? '' : part.raw;
  return mediaType.length === 0 && raw.length > 0;
}

/** 提取所有图片 part，跳过无法取字节的形状（既没有 raw 也没有 url） */
export function collectImageParts(parts: AgentPart[]): AgentImagePart[] {
  const images: AgentImagePart[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part: AgentPart = parts[i];
    if (!isImagePart(part)) {
      continue;
    }
    const raw: string = part.raw === undefined ? '' : part.raw;
    if (raw.length > 0) {
      images.push({ kind: 'base64', value: raw });
      continue;
    }
    const url: string = part.url === undefined ? '' : part.url;
    if (url.length > 0) {
      images.push({ kind: 'uri', value: url });
    }
  }
  return images;
}

/** 文本 part 拼成一句 query（小艺一般只发一个，多段时按顺序连） */
export function joinTextParts(parts: AgentPart[]): string {
  const chunks: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part: AgentPart = parts[i];
    if (isImagePart(part)) {
      continue;
    }
    const text: string = part.text === undefined ? '' : part.text.trim();
    if (text.length > 0) {
      chunks.push(text);
    }
  }
  return chunks.join('\n');
}
