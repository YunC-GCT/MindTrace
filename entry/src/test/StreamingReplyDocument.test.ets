/**
 * StreamingReplyDocument.test.ets — #142 StreamingReplyDocument 纯逻辑验收测试
 *
 * 路径: entry/src/test/StreamingReplyDocument.test.ets
 * 职责: 验证 append-only 增量、raw offset、block lifecycle、native Markdown/公式 seam 与 geometry。
 * 依赖: @ohos/hypium; entry/src/main/ets/services/StreamingReplyDocument。
 * 数据流: Hypium fixture delta → StreamingReplyDocument → block/projection/geometry 断言
 * ArkTS 1.1 strict 适配: 使用显式类型与 helper，避免 any/unknown 和解构。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  BlockPatch,
  DocumentGeometryState,
  NativeMarkdownProjection,
  ReplyBlockSnapshot,
  StreamingReplyDocument,
} from '../main/ets/services/StreamingReplyDocument';

function patchKinds(patches: BlockPatch[]): string {
  const values: string[] = [];
  for (const patch of patches) {
    values.push(patch.block.kind + ':' + patch.block.phase);
  }
  return values.join(',');
}

function findBlock(blocks: ReplyBlockSnapshot[], blockId: string): ReplyBlockSnapshot {
  for (const block of blocks) {
    if (block.blockId === blockId) {
      return block;
    }
  }
  throw new Error('missing block ' + blockId);
}

export default function streamingReplyDocumentTest(): void {
  describe('StreamingReplyDocument.issue142_delta', () => {
    it('accepts append-only deltas and returns block patches', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      const first: BlockPatch[] = document.applyDelta('# 标题\n');
      const second: BlockPatch[] = document.applyDelta('正文\n\n');

      expect(first.length > 0).assertTrue();
      expect(second.length > 0).assertTrue();
      expect(document.rawBody()).assertEqual('# 标题\n正文\n\n');
      expect(document.blocks().length).assertEqual(2);
    });

    it('rejects a delta after finalization without changing the raw body', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('原始');
      document.finalize();
      let rejected: boolean = false;
      try {
        document.applyDelta('替换');
      } catch (error) {
        rejected = error instanceof Error && error.message.indexOf('finalized message') >= 0;
      }

      expect(rejected).assertTrue();
      expect(document.rawBody()).assertEqual('原始');
    });

    it('uses raw UTF-16 start offsets in stable block ids', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('😀 前言\n\n正文');
      const blocks: ReplyBlockSnapshot[] = document.blocks();

      expect(blocks[0].blockId).assertEqual('message-142#0');
      expect(blocks[1].blockId).assertEqual('message-142#7');
      expect(blocks[1].rawText).assertEqual('正文');
    });

    it('does not reparse a sealed prefix while the open tail grows', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('第一段\n\n第二');
      const firstBlocks: ReplyBlockSnapshot[] = document.blocks();
      const sealedId: string = firstBlocks[0].blockId;
      const sealedScanCount: number = firstBlocks[0].parseCount;
      document.applyDelta('段继续');
      const secondBlocks: ReplyBlockSnapshot[] = document.blocks();

      expect(findBlock(secondBlocks, sealedId).phase).assertEqual('sealed');
      expect(findBlock(secondBlocks, sealedId).parseCount).assertEqual(sealedScanCount);
      expect(document.openTailStablePrefixLen() > 0).assertTrue();
      expect(document.lastScanStartOffset() > 0).assertTrue();
    });
  });

  describe('StreamingReplyDocument.issue142_seal', () => {
    it('seals headings and lists at a complete line boundary', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      const patches: BlockPatch[] = document.applyDelta('# 标题\n- 一\n- 二\n\n');
      const blocks: ReplyBlockSnapshot[] = document.blocks();

      expect(patchKinds(patches)).assertContain('heading:sealed');
      expect(blocks[0].phase).assertEqual('sealed');
      expect(blocks[1].kind).assertEqual('list');
      expect(blocks[1].phase).assertEqual('sealed');
    });

    it('keeps code fences and inline code from triggering text seals', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('```\n**not bold**\n\n');
      expect(document.blocks()[0].phase).assertEqual('open');
      document.applyDelta('```\n下一段\n\n');

      expect(document.blocks()[0].kind).assertEqual('code');
      expect(document.blocks()[0].phase).assertEqual('sealed');
      expect(document.blocks()[0].renderText).assertContain('**not bold**\n');
    });

    it('keeps an unclosed inline marker in the open tail', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('正文 **未闭合\n\n');

      expect(document.blocks()[0].phase).assertEqual('open');
      document.applyDelta('** 后续\n\n');
      expect(document.blocks()[0].phase).assertEqual('sealed');
    });

    it('keeps list and quote tails open when inline markers are unclosed', 0, () => {
      const listDocument: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      listDocument.applyDelta('- **未闭合\n\n');
      expect(listDocument.blocks()[0].kind).assertEqual('list');
      expect(listDocument.blocks()[0].phase).assertEqual('open');

      const quoteDocument: StreamingReplyDocument = new StreamingReplyDocument('message-143');
      quoteDocument.applyDelta('> $x\n\n');
      expect(quoteDocument.blocks()[0].kind).assertEqual('quote');
      expect(quoteDocument.blocks()[0].phase).assertEqual('open');
    });

    it('creates a formula placeholder and seals the same slot after closure', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('$$\nx^2');
      const open: ReplyBlockSnapshot = document.blocks()[0];
      document.applyDelta('\n$$');
      const closed: ReplyBlockSnapshot = document.blocks()[0];

      expect(open.kind).assertEqual('formula');
      expect(open.phase).assertEqual('open');
      expect(open.renderBackend).assertEqual('arkweb_slot');
      expect(open.placeholderText).assertContain('公式生成中');
      expect(closed.phase).assertEqual('sealed');
      expect(closed.renderBackend).assertEqual('arkweb_slot');
      expect(closed.blockId).assertEqual(open.blockId);
      expect(closed.formulaSlotId).assertEqual(open.formulaSlotId);
      expect(closed.pendingRenderWork).assertTrue();
    });
  });

  describe('StreamingReplyDocument.issue142_projection', () => {
    it('projects supported Markdown without sending ordinary text to WebView', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('## **标题**\n普通 `代码`\n');
      document.finalize();
      const blocks: ReplyBlockSnapshot[] = document.blocks();

      expect(blocks[0].renderBackend).assertEqual('styled_string');
      expect(blocks[0].renderText).assertEqual('**标题**');
      expect(blocks[1].renderBackend).assertEqual('styled_string');
      expect(blocks[1].renderText).assertEqual('普通 `代码`');
    });

    it('preserves code content and escapes unsupported syntax into fallback text', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('```ts\na < b && c > d\n```\n<a>链接</a>\n');
      document.finalize();
      const blocks: ReplyBlockSnapshot[] = document.blocks();

      expect(blocks[0].kind).assertEqual('code');
      expect(blocks[0].renderText).assertEqual('a < b && c > d\n');
      expect(blocks[0].renderBackend).assertEqual('styled_string');
      expect(blocks[1].kind).assertEqual('fallback');
      expect(blocks[1].renderText).assertContain('&lt;');
      expect(blocks[1].renderText).assertContain('&gt;');
    });

    it('normalizes formula copies through ContentProtocol while preserving raw offsets', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('$$\n\\fract{1}{2}\n$$');
      const block: ReplyBlockSnapshot = document.blocks()[0];

      expect(block.blockId).assertEqual('message-142#0');
      expect(block.renderText).assertEqual('\\frac{1}{2}');
      expect(block.rawText).assertEqual('$$\n\\fract{1}{2}\n$$');
    });

    it('keeps formula placeholder text inside the configured cap', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('$$\n12345678901234567890123456789012345678901');
      const block: ReplyBlockSnapshot = document.blocks()[0];

      expect(block.placeholderText.length).assertEqual('公式生成中: '.length + 40);
    });

    it('keeps inline formula slots on the custom span seam with raw offsets', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('段落 $x');
      const open: ReplyBlockSnapshot = document.blocks()[0];
      document.applyDelta('+y$ 结束\n\n');
      const closed: ReplyBlockSnapshot = document.blocks()[0];
      const projection: NativeMarkdownProjection | undefined = document.nativeProjection(closed.blockId);

      expect(closed.inlineFormulaSlots.length).assertEqual(1);
      expect(closed.inlineFormulaSlots[0].renderBackend).assertEqual('custom_span');
      expect(closed.inlineFormulaSlots[0].rawStartOffset).assertEqual(3);
      expect(closed.inlineFormulaSlots[0].slotId).assertEqual(open.inlineFormulaSlots[0].slotId);
      expect(closed.inlineFormulaSlots[0].widthVp >= open.inlineFormulaSlots[0].widthVp).assertTrue();
      expect(projection !== undefined).assertTrue();
      if (projection !== undefined) {
        expect(projection.inlineFormulaBackend).assertEqual('custom_span');
        expect(projection.customSpanSlotIds[0]).assertEqual(closed.inlineFormulaSlots[0].slotId);
      }
    });
  });

  describe('StreamingReplyDocument.issue142_finalize_geometry', () => {
    it('finalizes before render work settles and accepts later geometry changes', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('$$\nx\n$$');
      document.finalize();
      let state: DocumentGeometryState = document.geometryState();
      expect(state.finalized).assertTrue();
      expect(state.allBlocksSettled).assertFalse();

      const blockId: string = document.blocks()[0].blockId;
      document.applyBlockHeight(blockId, 72);
      document.setSchedulerQueueEmpty(true);
      state = document.geometryState();
      expect(state.geometryEvents).assertEqual(1);
      expect(state.allBlocksSettled).assertTrue();
      expect(state.totalHeight).assertEqual(72);
      expect(state.lastHeightDelta).assertEqual(14);
    });

    it('ignores geometry for an unknown block without changing settled state', 0, () => {
      const document: StreamingReplyDocument = new StreamingReplyDocument('message-142');
      document.applyDelta('文本');
      document.finalize();
      document.applyBlockHeight('missing', 99);

      expect(document.geometryState().geometryEvents).assertEqual(0);
      expect(document.geometryState().allBlocksSettled).assertTrue();
    });
  });
}
