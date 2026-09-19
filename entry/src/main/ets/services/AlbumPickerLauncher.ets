/**
 * AlbumPickerLauncher.ets — 拉起 HarmonyOS 系统相册选择器
 *
 * 路径: entry/src/main/ets/services/AlbumPickerLauncher.ets
 * 职责: 封装 photoAccessHelper.PhotoViewPicker (来自 @kit.MediaLibraryKit)
 *       拉起系统相册让用户选图片, 选完返回 URI 数组
 * 依赖: @kit.MediaLibraryKit (photoAccessHelper), @kit.AbilityKit (Context)
 *
 * 特性: 拉起的是 HarmonyOS 系统相册 (类似系统 Files), 无需单独申请媒体权限
 *        (PhotoPicker 自管权限)
 *
 * 用法:
 *   import { AlbumPickerLauncher } from '../services/AlbumPickerLauncher';
 *   const uris: string[] = await AlbumPickerLauncher.pick(context);
 *   if (uris.length > 0) { vm.setImagePreview(uris[0]); }
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';

export class AlbumPickerLauncher {
  /**
   * 拉起系统相册选择器, 单选图片
   * @param context UIAbilityContext
   * @returns 选中图片的 URI 数组 (空数组 = 用户取消)
   * @throws 系统错误时抛出异常
   */
  static async pick(context: common.UIAbilityContext): Promise<string[]> {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    options.isPhotoTakingSupported = false;

    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    return result.photoUris;
  }
}
