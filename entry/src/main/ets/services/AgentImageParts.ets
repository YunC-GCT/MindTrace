/**
 * AgentImageParts.ets — A2A 请求 part 的形状判定与图片提取（纯函数）
 *
 * 路径: entry/src/main/ets/services/AgentImageParts.ets
 * 职责: 把小艺请求里的 parts[] 归一成「文本 part / 图片 part」两种，图片供 OCR 节点使用
 * 依赖: 无（不碰 Context、不碰 Kit，可直接单测）
 *
 * 协议事实（端A2A · Part 结构定义）：
 *   图片走 Part<url>：{ url, filename, mediaType: 'image/png' }，支持双向传递；
 *   也兼容 { mediaType: 'image/*', raw: '<base64>' } 与 data 里直接放 base64 的写法。
 *   注意：小艺侧要在开放平台「输入文件设置 → 照片设置 → 支持上传照片」开启后才会下发图片 part；
 *   开关关闭时用户发的图不会到扩展进程（实测只收到一个 text 为空的 text part）。
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

const DATA_URL_PREFIX: string = 'data:';

/** mediaType 以 image/ 开头即图片；缺失 mediaType 但有 raw 的按图片兜底 */
export function isImagePart(part: AgentPart): boolean {
  const mediaType: string = part.mediaType === undefined ? '' : part.mediaType;
  if (mediaType.indexOf('image/') === 0) {
    return true;
  }
  const raw: string = part.raw === undefined ? '' : part.raw;
  return mediaType.length === 0 && raw.length > 0;
}

/** data:image/png;base64,xxxx 去掉前缀，只留 base64 正文 */
function stripDataUrl(value: string): string {
  const comma: number = value.indexOf(',');
  if (value.indexOf(DATA_URL_PREFIX) === 0 && comma > 0) {
    return value.substring(comma + 1);
  }
  return value;
}

/** 从 part 里取图片字节的来源：raw > url > data(string) */
export function pickImageSource(part: AgentPart): AgentImagePart | undefined {
  const raw: string = part.raw === undefined ? '' : part.raw;
  if (raw.length > 0) {
    return { kind: 'base64', value: raw };
  }
  const url: string = part.url === undefined ? '' : part.url;
  if (url.length > 0) {
    return { kind: 'uri', value: url };
  }
  const data: string | number | boolean | object | undefined = part.data;
  if (typeof data === 'string' && data.length > 0) {
    return { kind: 'base64', value: stripDataUrl(data) };
  }
  return undefined;
}

/** 提取所有图片 part，跳过无法取字节的形状 */
export function collectImageParts(parts: AgentPart[]): AgentImagePart[] {
  const images: AgentImagePart[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part: AgentPart = parts[i];
    if (!isImagePart(part)) {
      continue;
    }
    const source: AgentImagePart | undefined = pickImageSource(part);
    if (source !== undefined) {
      images.push(source);
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
