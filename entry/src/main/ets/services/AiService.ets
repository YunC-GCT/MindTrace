// ============================================================================
//  services/AiService.ets — 拍照→AI 整链入口
//  ----------------------------------------------------------------------------
//  职责: 拍照/选图/文本的统一入口,把外部输入转成 KnowledgeUnit 并入库。
//
//  接口约定:
//    - capture(imageUri, userText?): Promise<KnowledgeUnit>
//        拍照/相册的入口。绝不只走 LLM 对话,必须进入 capture pipeline:
//        Dispatcher -> image/OCR/MCP 识别 -> 分类 -> 知识结构化 -> 入库。
//    - captureText(text): Promise<KnowledgeUnit>
//        文本入口。同样的知识入库契约,跳过图像识别。
//
//  UI 端约束: 凡是发图的,都必须调 capture() 而不是 LLM 对话。
//
//  整链调用链:
//    ImageUriResolver.resolve(uri)  // file:// URI 复制到沙箱
//    -> Dispatcher.dispatch(payload)  // 调度中枢
//      -> TypeClassifier.classify()   // OCR + DeepSeek 3×3 分类
//        -> OcrTool.recognize()       // 本地 FastAPI HTTP OCR
//      -> KnowledgeModel.structure()  // 模板填充 + 真值检验
//    -> NoteDao.insert(unit)         // RDB 持久化
//  ============================================================================

import {
  KnowledgeUnit,
  ClassificationResult,
  DispatchRequest,
  DispatchAnalysisResult,
  DispatchPayload,
  Logger,
} from 'common';
import { AgentState, CaptureGraph, CaptureGraphError, Dispatcher, NoteDaoInterface } from 'agents';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { ImageUriResolver, ResolvedImageFile } from './ImageUriResolver';
import { NoteDao } from '../database/NoteDao';
import { DatabaseHelper } from 'common';
import { UiDataCacheService } from './UiDataCacheService';
import { NoteDaoAdapter } from '../adapters/NoteDaoAdapter';

const log: Logger = new Logger('AiService');

export class AiService {
  // UIAbilityContext 引用,capture() 准备图片文件时用
  private context?: common.UIAbilityContext;

  constructor(context?: common.UIAbilityContext) {
    this.context = context;
  }

  // 拍照/相册入口:把图片处理成 KnowledgeUnit 并持久化
  async capture(imageUri: string, userText?: string): Promise<KnowledgeUnit> {
    log.info('capture start, imageUri=' + imageUri);
    if (this.context === undefined) {
      throw new Error('AiService.capture 需要 UIAbilityContext 来准备图片文件');
    }

    // 1) 把 file:// URI 复制到沙箱(本地路径,OCR/Dao 都能访问)
    const resolved: ResolvedImageFile = await new ImageUriResolver(this.context).resolve(imageUri);
    log.info('capture 图片已准备,本地路径=' + resolved.localPath);

    // 2) 走整链
    return this.processAndPersist({
      kind: 'image',
      imageUri: resolved.localPath,
      userText: userText,
    });
  }

  // 图片识别入口: 只 OCR + 分类，返回识别内容，不生成笔记、不入库
  async analyzeImage(imageUri: string, userText?: string): Promise<ClassificationResult> {
    log.info('analyzeImage start, imageUri=' + imageUri);
    if (this.context === undefined) {
      throw new Error('AiService.analyzeImage 需要 UIAbilityContext 来准备图片文件');
    }

    const resolved: ResolvedImageFile = await new ImageUriResolver(this.context).resolve(imageUri);
    const req: DispatchRequest = {
      source: 'app',
      payload: {
        kind: 'image',
        imageUri: resolved.localPath,
        userText: userText,
      },
    };

    const dispatcher: Dispatcher = new Dispatcher();
    const graph: CaptureGraph = dispatcher.buildGraph(req, { persist: false });
    const initial: AgentState = {
      captureText: '',
      currentStep: 'START',
      persist: false,
    };
    const finalState: AgentState = await graph.run(initial, { persist: false });
    if (finalState.error !== undefined || finalState.classification === undefined) {
      throw new Error(finalState.error?.message ?? '识别失败');
    }
    return finalState.classification;
  }

  // 内部: 把 entry 端 NoteDao 适配成 agents 端 NoteDaoInterface
  private async buildNoteDao(): Promise<NoteDaoInterface> {
    if (this.context === undefined) {
      throw new Error('AiService.buildNoteDao 需要 UIAbilityContext');
    }
    let rdb: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (rdb === null) {
      rdb = await DatabaseHelper.init(this.context);
    }
    const noteDao: NoteDao = new NoteDao(rdb);
    const adapter: NoteDaoAdapter = new NoteDaoAdapter((unit) => noteDao.insert(unit));
    UiDataCacheService.invalidateNotesSnapshots();
    return adapter;
  }

  // 文本入口:同样的知识入库契约,跳过图像识别
  async captureText(text: string): Promise<KnowledgeUnit> {
    log.info('captureText start, 长度=' + text.length.toString());
    return this.processAndPersist({
      kind: 'text',
      text: text,
    });
  }

  // 内部: 调度 -> 校验 -> 入库
  private async processAndPersist(payload: DispatchPayload): Promise<KnowledgeUnit> {
    // 1) 构造调度请求
    const req: DispatchRequest = { source: 'app', payload };

    // 2) 准备 NoteDao 适配器, 注入到 CaptureGraph PersistNode
    const dao: NoteDaoInterface = await this.buildNoteDao();

    // 3) 构造 Dispatcher, 显式传入 dao (T6 收口时再决定是否删除 dao 参数)
    const dispatcher: Dispatcher = new Dispatcher();
    const graph: CaptureGraph = dispatcher.buildGraph(req, { persist: true, dao });
    const initial: AgentState = {
      captureText: payload.kind === 'text' ? payload.text : '',
      currentStep: 'START',
      persist: true,
    };
    const finalState: AgentState = await graph.run(initial, { persist: true });
    const error: CaptureGraphError | undefined = finalState.error;
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      throw new Error('处理失败: ' + error.message);
    }
    const unit: KnowledgeUnit | undefined = finalState.knowledgeUnit;
    if (unit === undefined) {
      throw new Error('处理失败: capture graph 未生成 KnowledgeUnit');
    }

    // 4) UI 缓存(原行为保留)
    console.info('[AiService] ====== KnowledgeUnit dump start ======');
    console.info('[AiService] id=' + unit.id + ' title=' + unit.title);
    console.info('[AiService] content length=' + unit.content.length.toString() + ' chars');
    console.info('[AiService] content: ' + unit.content.substring(0, 500));
    console.info('[AiService] summary=' + unit.summary);
    console.info('[AiService] tags=' + JSON.stringify(unit.tags));
    console.info('[AiService] ====== KnowledgeUnit dump end ======');

    log.info('done, 笔记 id=' + unit.id
      + ', 类型=' + (unit.tags.length > 0 ? unit.tags[0] : '?'));

    return unit;
  }
}
