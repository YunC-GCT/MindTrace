/**
 * SessionsPanelController.ets — 会话删除确认控制器
 *
 * 路径: entry/src/main/ets/services/SessionsPanelController.ets
 * 职责: 封装 SessionsPanel 长按删除时的原生确认弹框。
 *       让 AgentFloatWindow 不直接处理 showDialog, 只调用 controller。
 *
 * 接口 (静态方法, 无状态):
 *   SessionsPanelController.requestDelete(prompt, sid, sessionName, onConfirm, onError): void
 *     弹出原生确认框; 用户确认后调用 onConfirm(sid); 弹框失败时调用 onError。
 *   SessionsPanelController.requestClearAll(prompt, onConfirm, onError): void
 *     弹出清空全部对话的确认框; 用户确认后调用 onConfirm(); 弹框失败时调用 onError。
 *
 * 依赖: @kit.ArkUI PromptAction; common 颜色 token
 */

import { PromptAction } from '@kit.ArkUI';
import { DANGER_BRIGHT, TEXT_3 } from 'common';

const DELETE_DIALOG_TITLE: string = '删除会话';
const DELETE_DIALOG_MSG_PREFIX: string = '确定要删除"';
const DELETE_DIALOG_MSG_SUFFIX: string = '"吗?该会话下的所有消息都会被清除。';
const DELETE_DIALOG_CONFIRM: string = '删除';
const DELETE_DIALOG_CANCEL: string = '取消';
const DELETE_DIALOG_CONFIRM_INDEX: number = 1;

const CLEAR_DIALOG_TITLE: string = '清空全部对话？';
const CLEAR_DIALOG_MSG: string =
  '将删除所有会话的聊天消息与聊天上下文，且无法恢复。已保存的知识笔记、复习记录和学习画像不会受影响。';
const CLEAR_DIALOG_CONFIRM: string = '清空';
const CLEAR_DIALOG_CANCEL: string = '取消';
const CLEAR_DIALOG_CONFIRM_INDEX: number = 1;

export class SessionsPanelController {
  static requestDelete(
    prompt: PromptAction,
    sid: string,
    sessionName: string,
    onConfirm: (sid: string) => void,
    onError: () => void
  ): void {
    try {
      prompt.showDialog({
        title: DELETE_DIALOG_TITLE,
        message: DELETE_DIALOG_MSG_PREFIX + sessionName + DELETE_DIALOG_MSG_SUFFIX,
        buttons: [
          { text: DELETE_DIALOG_CANCEL, color: TEXT_3 },
          { text: DELETE_DIALOG_CONFIRM, color: DANGER_BRIGHT },
        ],
      }).then((result): void => {
        if (result.index === DELETE_DIALOG_CONFIRM_INDEX) {
          onConfirm(sid);
        }
      }).catch((): void => {
        onError();
      });
    } catch (_e) {
      onError();
    }
  }

  static requestClearAll(
    prompt: PromptAction,
    onConfirm: () => void,
    onError: () => void
  ): void {
    try {
      prompt.showDialog({
        title: CLEAR_DIALOG_TITLE,
        message: CLEAR_DIALOG_MSG,
        buttons: [
          { text: CLEAR_DIALOG_CANCEL, color: TEXT_3 },
          { text: CLEAR_DIALOG_CONFIRM, color: DANGER_BRIGHT },
        ],
      }).then((result): void => {
        if (result.index === CLEAR_DIALOG_CONFIRM_INDEX) {
          onConfirm();
        }
      }).catch((): void => {
        onError();
      });
    } catch (_e) {
      onError();
    }
  }
}
