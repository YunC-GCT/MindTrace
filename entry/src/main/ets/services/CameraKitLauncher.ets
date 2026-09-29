/**
 * CameraKitLauncher.ets — 拉起 HarmonyOS 系统相机选择器
 *
 * 路径: entry/src/main/ets/services/CameraKitLauncher.ets
 * 职责: 封装 @ohos.multimedia.cameraPicker (来自 @kit.CameraKit), 拍完返回图片 URI
 * 依赖: @kit.CameraKit (cameraPicker + camera), @kit.AbilityKit (Context)
 *
 * 特性: 拉起的是 HarmonyOS 系统相机选择器, 无需申请相机权限
 *        (拍照发生在系统侧, 应用仅接收 PickerResult)
 *
 * 用法:
 *   import { CameraKitLauncher } from '../services/CameraKitLauncher';
 *   const uri: string = await CameraKitLauncher.capture(context);
 *   vm.setImagePreview(uri);
 */

import { cameraPicker, camera } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class CameraKitLauncher {
  /**
   * 拉起系统相机选择器, 拍摄完成后返回图片 URI
   * @param context UIAbilityContext (从 @kit.AbilityKit)
   * @returns 拍摄图片的 URI 字符串
   * @throws 用户取消 / 系统错误时抛出异常
   */
  static async capture(context: common.UIAbilityContext): Promise<string> {
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
    };
    const result: cameraPicker.PickerResult = await cameraPicker.pick(
      context,
      [cameraPicker.PickerMediaType.PHOTO],
      profile,
    );
    return result.resultUri;
  }
}
