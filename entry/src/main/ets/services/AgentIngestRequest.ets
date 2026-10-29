/**
 * AgentIngestRequest.ets — 入口层与整理层之间的数据契约
 *
 * 路径: entry/src/main/ets/services/AgentIngestRequest.ets
 * 职责: 把「小艺 text part / 小艺 image part / 应用内选图 / 系统分享」统一成一种请求，
 *       让整理链路只认这个结构，不再关心消息是从哪个入口进来的。
 * 依赖: services/AgentImageParts（图片项形状），无 Kit、无 Context
 *
 * 分层：入口 adapter（协议解析）→ AgentIngestRequest（本文件）→ AgentIngestService（编排）
 *       → OcrService（共享能力）→ Dispatcher（agent 链路）→ 写路径
 */

import { AgentImagePart } from './AgentImageParts';

/** 入口标识，用于日志与回执措辞；新增入口只加一个常量 */
export const INGEST_SOURCE_XIAOYI: string = 'xiaoyi';
export const INGEST_SOURCE_APP_PICKER: string = 'app-picker';
export const INGEST_SOURCE_APP_SHARE: string = 'app-share';

/** 一次整理请求：文字是主输入，图片存在时以图片识别结果为主 */
export interface AgentIngestRequest {
  /** INGEST_SOURCE_* */
  source: string;
  /** 用户打的字；图片入口里它是提示（「存笔记」），不是正文 */
  text: string;
  /** 待识别图片；空数组表示纯文字请求 */
  images: AgentImagePart[];
}

export function buildIngestRequest(source: string, text: string, images: AgentImagePart[]): AgentIngestRequest {
  return { source: source, text: text, images: images };
}

/** 是否有可整理的内容（空请求不该进模型，也不该入队） */
export function hasIngestPayload(request: AgentIngestRequest): boolean {
  return request.text.trim().length > 0 || request.images.length > 0;
}
