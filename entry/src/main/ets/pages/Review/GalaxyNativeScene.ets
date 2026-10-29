/**
 * GalaxyNativeScene.ets — 原生场景模板解析。
 * 路径: pages/Review/GalaxyNativeScene.ets
 * 职责: 隔离 GLB 导入层级与业务模板名称。
 * 依赖: ArkGraphics3D 类型
 * 数据流: Scene → findGalaxyTemplate → 原生适配器
 */
import type { Node, Scene, Vec2, Vec3, Vec4, Mat4x4, Quaternion } from '@kit.ArkGraphics3D'

export function galaxyRaycastPosition(x: number, y: number, width: number, height: number): Vec2 {
  // Camera.raycast consumes normalized screen coordinates [0, 1] on native API 24.
  return { x: x / Math.max(1, width), y: y / Math.max(1, height) }
}

export function findGalaxyTemplate(scene: Scene, name: string): Node | null {
  if (scene.root === null) return null
  const pending: Node[] = [scene.root]
  let match: Node | null = null
  while (pending.length > 0) {
    const current: Node = pending.pop()!
    if (current.name === name) {
      if (match !== null) throw new Error('native_scene_template_ambiguous: ' + name)
      match = current
    }
    for (let index: number = 0; index < current.children.count(); index++) {
      const child: Node | null = current.children.get(index)
      if (child !== null) pending.push(child)
    }
  }
  return match
}

export function rotateGalaxyPoint(point: Vec3, yaw: number, pitch: number): Vec3 {
  const x: number = point.x * Math.cos(yaw) + point.z * Math.sin(yaw)
  const z: number = -point.x * Math.sin(yaw) + point.z * Math.cos(yaw)
  return { x: x, y: point.y * Math.cos(pitch) - z * Math.sin(pitch),
    z: point.y * Math.sin(pitch) + z * Math.cos(pitch) }
}

export function galaxyEdgeRotation(direction: Vec3): Quaternion {
  const length: number = Math.hypot(direction.x, direction.y, direction.z)
  if (length < 0.00001) return { x: 0, y: 0, z: 0, w: 1 }
  const x: number = direction.x / length
  if (x < -0.999999) return { x: 0, y: 0, z: 1, w: 0 }
  const norm: number = Math.sqrt(2 * (1 + x))
  return { x: 0, y: -direction.z / length / norm, z: direction.y / length / norm, w: (1 + x) / norm }
}

function transformPoint(matrix: Mat4x4, point: Vec4): Vec4 {
  return {
    x: matrix.x.x * point.x + matrix.y.x * point.y + matrix.z.x * point.z + matrix.w.x * point.w,
    y: matrix.x.y * point.x + matrix.y.y * point.y + matrix.z.y * point.z + matrix.w.y * point.w,
    z: matrix.x.z * point.x + matrix.y.z * point.y + matrix.z.z * point.z + matrix.w.z * point.w,
    w: matrix.x.w * point.x + matrix.y.w * point.y + matrix.z.w * point.z + matrix.w.w * point.w,
  }
}

export function projectGalaxyPoint(point: Vec3, view: Mat4x4, projection: Mat4x4, width: number, height: number): Vec2 | null {
  const cameraPoint: Vec4 = transformPoint(view, { x: point.x, y: point.y, z: point.z, w: 1 })
  const clip: Vec4 = transformPoint(projection, cameraPoint)
  if (clip.w <= 0.0001) return null
  const x: number = clip.x / clip.w
  const y: number = clip.y / clip.w
  if (Math.abs(x) > 1.1 || Math.abs(y) > 1.1) return null
  // ArkGraphics3D's projection already includes the native render-target Y flip.
  return { x: (x + 1) * width / 2, y: (y + 1) * height / 2 }
}
