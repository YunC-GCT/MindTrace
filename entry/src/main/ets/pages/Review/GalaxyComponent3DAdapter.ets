// ============================================================================
//  pages/Review/GalaxyComponent3DAdapter.ets - native Component3D renderer
// ============================================================================

import {
  Camera,
  Node,
  RaycastResult,
  Scene,
  Vec2,
  Geometry,
  Material,
  MaterialType,
  MetallicRoughnessMaterial,
  NodeType,
  EnvironmentBackgroundType,
} from '@kit.ArkGraphics3D'
import { TEXT, TEXT_2, BG_CARD, BORDER, R_MD, S_2 } from 'common'
import { AppIcon } from '../../shared/atoms/AppIcon'
import { findGalaxyTemplate, rotateGalaxyPoint, galaxyEdgeRotation, projectGalaxyPoint, galaxyRaycastPosition } from './GalaxyNativeScene'
import type { GalaxyGraphEdge, GalaxyGraphNode, GalaxyGraphSnapshot } from './GalaxyGraphProjection'
import {
  GalaxyNoopCallbacks,
  GalaxyPerformanceSample,
  GalaxyRendererCallbacks,
} from './GalaxyRendererContracts'

const CAMERA_DEFAULT_DISTANCE: number = 120
const CAMERA_MIN_DISTANCE: number = 38
const CAMERA_MAX_DISTANCE: number = 130
const NODE_TEMPLATE_PATH: string = 'NodeTemplate'
const CAMERA_PATH: string = 'GalaxyCamera'
const PREREQUISITE_TEMPLATE_PATH: string = 'PrerequisiteEdgeTemplate'
const RELATED_TEMPLATE_PATH: string = 'RelatedEdgeTemplate'

class NativeNodeView {
  id: string = ''
  node: Node
  baseX: number = 0
  baseY: number = 0
  baseZ: number = 0
  material: Material | null = null

  constructor(id: string, node: Node, x: number, y: number, z: number) {
    this.id = id
    this.node = node
    this.baseX = x
    this.baseY = y
    this.baseZ = z
  }
}

class NativeEdgeView {
  edge: GalaxyGraphEdge
  node: Node

  constructor(edge: GalaxyGraphEdge, node: Node) {
    this.edge = edge
    this.node = node
  }
}

@Observed
class NativeLabelView {
  id: string = ''
  label: string = ''
  x: number = 0
  y: number = 0
  visible: boolean = false

  constructor(id: string, label: string, x: number, y: number) {
    this.id = id
    this.label = label
    this.x = x
    this.y = y
  }
}

@Component
struct NativeGalaxyLabel {
  @ObjectLink label: NativeLabelView
  @Prop selectedId: string = ''

  build() {
    Text(this.label.label)
      .fontSize(11)
      .fontColor(this.label.id === this.selectedId ? TEXT : TEXT_2)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .width(104)
      .padding({ left: 5, right: 5, top: 3, bottom: 3 })
      .backgroundColor('#C010131A')
      .border({ width: 0.5, color: BORDER })
      .borderRadius(R_MD)
      .position({ x: this.label.x - 52, y: this.label.y - 28 })
      .visibility(this.label.visible ? Visibility.Visible : Visibility.Hidden)
      .accessibilityText(this.label.label)
      .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct GalaxyComponent3DAdapter {
  @Prop @Watch('onSnapshotChanged') snapshot: GalaxyGraphSnapshot = { nodes: [], edges: [] }
  @Prop @Watch('onSelectionChanged') selectedId: string = ''
  @Prop @Watch('onPausedChanged') paused: boolean = false
  @Prop viewportWidth: number = 360
  @Prop viewportHeight: number = 520
  callbacks: GalaxyRendererCallbacks = new GalaxyNoopCallbacks()
  // Keep native resource lifetime separate from the reactive readiness flag.
  private scene: Scene | null = null
  private templateScene: Scene | null = null
  @State private hasScene: boolean = false
  @State private labels: NativeLabelView[] = []
  private camera: Camera | null = null
  private nodeViews: NativeNodeView[] = []
  private edgeViews: NativeEdgeView[] = []
  private nodePathToId: Map<string, string> = new Map<string, string>()
  private rotationAngle: number = 0
  private panStartAngle: number = 0
  private pitchAngle: number = 0
  private panStartPitch: number = 0
  private cameraDistance: number = CAMERA_DEFAULT_DISTANCE
  private pinchStartDistance: number = CAMERA_DEFAULT_DISTANCE
  private loadGeneration: number = 0
  private graphGeneration: number = 0
  private labelTimer: number = -1
  private labelFramesRemaining: number = 0

  aboutToAppear(): void {
    this.loadScene()
  }

  aboutToDisappear(): void {
    this.release()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.hasScene && this.scene !== null) {
        Component3D({ scene: this.scene })
          .width('100%')
          .height('100%')
          .onAppear((): void => this.updateCameraDistance())
          .onAreaChange((): void => this.onViewportChanged())
          .gesture(
            GestureGroup(
              GestureMode.Parallel,
              PanGesture({ direction: PanDirection.All })
                .onActionStart((): void => {
                  this.panStartAngle = this.rotationAngle
                  this.panStartPitch = this.pitchAngle
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.rotationAngle = this.panStartAngle + event.offsetX * 0.006
                  this.pitchAngle = this.clamp(this.panStartPitch + event.offsetY * 0.006, -1.4, 1.4)
                  this.applySceneTransforms()
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart((): void => {
                  this.pinchStartDistance = this.cameraDistance
                })
                .onActionUpdate((event: GestureEvent): void => {
                  const scale: number = Math.max(0.1, event.scale)
                  this.cameraDistance = this.clamp(
                    this.pinchStartDistance / scale,
                    CAMERA_MIN_DISTANCE,
                    CAMERA_MAX_DISTANCE,
                  )
                  this.updateCameraDistance()
                }),
              TapGesture({ count: 1 })
                .onAction((event: GestureEvent): void => this.handleTap(event)),
            )
          )

        ForEach(this.labels,
          (label: NativeLabelView): void => {
            NativeGalaxyLabel({ label: label, selectedId: this.selectedId })
          },
          (label: NativeLabelView): string => label.id,
        )

        Button() {
          AppIcon({ name: 'refresh', iconSize: 19, color: TEXT, strokeWidth: 1.8 })
        }
        .width(40)
        .height(40)
        .margin({ left: S_2, top: S_2 })
        .borderRadius(R_MD)
        .backgroundColor(BG_CARD)
        .border({ width: 0.5, color: BORDER })
        .onClick((): void => this.resetCamera())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF0A0C10')
  }

  setSnapshot(snapshot: GalaxyGraphSnapshot): void {
    this.snapshot = snapshot
    this.rebuildGraph()
  }

  setSelection(id: string): void {
    this.selectedId = id
    this.applySelection()
  }

  resetCamera(): void {
    this.rotationAngle = 0
    this.pitchAngle = 0
    this.cameraDistance = CAMERA_DEFAULT_DISTANCE
    this.applySceneTransforms()
    this.updateCameraDistance()
  }

  pause(): void {
    this.stopLabelRefresh()
  }

  resume(): void {
    this.requestRender()
  }

  release(): void {
    this.loadGeneration++
    this.stopLabelRefresh()
    this.clearGraphNodes()
    if (this.scene !== null) {
      try { this.scene.destroy() } catch (_error) {}
    }
    this.scene = null
    if (this.templateScene !== null) {
      try { this.templateScene.destroy() } catch (_error) {}
      this.templateScene = null
    }
    this.hasScene = false
    this.camera = null
    this.labels = []
  }

  private async loadScene(): Promise<void> {
    const generation: number = ++this.loadGeneration
    try {
      const loaded: Scene = await Scene.load($rawfile('galaxy3d/native/galaxy-scene.glb'))
      if (generation !== this.loadGeneration) {
        loaded.destroy()
        return
      }
      const cameraNode: Node | null = this.findNode(loaded, CAMERA_PATH)
      const nodeTemplate: Node | null = this.findNode(loaded, NODE_TEMPLATE_PATH)
      const prerequisiteTemplate: Node | null = this.findNode(loaded, PREREQUISITE_TEMPLATE_PATH)
      const relatedTemplate: Node | null = this.findNode(loaded, RELATED_TEMPLATE_PATH)
      if (cameraNode === null || nodeTemplate === null
        || prerequisiteTemplate === null || relatedTemplate === null) {
        console.warn('[GalaxyNative] template lookup failed: camera=' + String(cameraNode !== null)
          + ' node=' + String(nodeTemplate !== null) + ' prerequisite=' + String(prerequisiteTemplate !== null)
          + ' related=' + String(relatedTemplate !== null) + ' root=' + (loaded.root?.path ?? 'null'))
        loaded.destroy()
        this.callbacks.onFailure('native_scene_templates_missing')
        return
      }
      let templates: Scene
      try {
        templates = await Scene.load($rawfile('galaxy3d/native/galaxy-scene.glb'))
      } catch (error) {
        loaded.destroy()
        throw new Error(this.errorMessage(error))
      }
      if (generation !== this.loadGeneration) {
        templates.destroy()
        loaded.destroy()
        return
      }
      this.scene = loaded
      this.templateScene = templates
      this.camera = cameraNode as Camera
      this.camera.enabled = true
      this.camera.msaa = true
      this.camera.clearColor = { r: 0.003, g: 0.004, b: 0.006, a: 1 }
      loaded.environment.backgroundType = EnvironmentBackgroundType.BACKGROUND_NONE
      loaded.environment.indirectDiffuseFactor = { x: 0.25, y: 0.25, z: 0.3, w: 1 }
      loaded.environment.indirectSpecularFactor = { x: 0.25, y: 0.25, z: 0.3, w: 1 }
      console.info('[GalaxyNative] scene templates resolved: camera=' + cameraNode.path + cameraNode.name
        + ' node=' + nodeTemplate.path + nodeTemplate.name)
      nodeTemplate.visible = false
      prerequisiteTemplate.visible = false
      relatedTemplate.visible = false
      this.rebuildGraph()
      this.hasScene = true
      console.info('[GalaxyNative] ready renderer=native nodes=' + this.nodeViews.length.toString())
      this.callbacks.onReady()
      this.callbacks.onPerformance(new GalaxyPerformanceSample('native', 0, 0, false))
    } catch (error) {
      this.callbacks.onFailure('native_scene_load_failed: ' + this.errorMessage(error))
    }
  }

  private rebuildGraph(): void {
    if (this.scene === null || this.scene.root === null || this.templateScene === null) {
      return
    }
    const nodeTemplate: Node | null = this.findNode(this.templateScene, NODE_TEMPLATE_PATH)
    const prerequisiteTemplate: Node | null = this.findNode(this.templateScene, PREREQUISITE_TEMPLATE_PATH)
    const relatedTemplate: Node | null = this.findNode(this.templateScene, RELATED_TEMPLATE_PATH)
    if (nodeTemplate === null || prerequisiteTemplate === null || relatedTemplate === null) {
      this.callbacks.onFailure('native_scene_templates_missing')
      return
    }
    this.clearGraphNodes()
    let index: number = 0
    for (const graphNode of this.snapshot.nodes) {
      const angle: number = index * 2.399963
      const radius: number = 7 + Math.sqrt(index + 1) * 7.8
      const x: number = Math.cos(angle) * radius
      const y: number = Math.sin(angle) * radius * 0.68
      const z: number = Math.sin(index * 1.73) * 7
      const sceneNode: Node = this.scene.importNode('GalaxyNode_' + index.toString(), nodeTemplate, this.scene.root)
      if (!sceneNode) throw new Error('native_node_import_failed')
      sceneNode.visible = true
      const scale: number = 0.7 + graphNode.mastery * 0.45
      sceneNode.scale = { x: scale, y: scale, z: scale }
      const view: NativeNodeView = new NativeNodeView(graphNode.id, sceneNode, x, y, z)
      this.nodeViews.push(view)
      this.applyNodeMaterial(view, graphNode.color, this.graphGeneration)
      this.nodePathToId.set(sceneNode.name, graphNode.id)
      index++
    }
    index = 0
    for (const edge of this.snapshot.edges) {
      const template: Node = edge.type === 'prerequisite' ? prerequisiteTemplate : relatedTemplate
      const edgeNode: Node = this.scene.importNode('GalaxyEdge_' + index.toString(), template, this.scene.root)
      if (!edgeNode) throw new Error('native_edge_import_failed')
      edgeNode.visible = true
      this.edgeViews.push(new NativeEdgeView(edge, edgeNode))
      index++
    }
    this.applySceneTransforms()
    this.applySelection()
  }

  private clearGraphNodes(): void {
    this.graphGeneration++
    for (const view of this.nodeViews) {
      try { view.node.destroy() } catch (_error) {}
      try { view.material?.destroy() } catch (_error) {}
    }
    for (const view of this.edgeViews) {
      try { view.node.destroy() } catch (_error) {}
    }
    this.nodeViews = []
    this.edgeViews = []
    this.nodePathToId.clear()
  }

  private applyNodeMaterial = async (view: NativeNodeView, color: string, generation: number): Promise<void> => {
    if (this.scene === null) return
    try {
      const resource: Material = await this.scene.getResourceFactory().createMaterial(
        { name: 'KnowledgeMaterial_' + view.node.name }, MaterialType.METALLIC_ROUGHNESS)
      if (generation !== this.graphGeneration || this.scene === null) {
        resource.destroy()
        return
      }
      view.material = resource
      const material: MetallicRoughnessMaterial = resource as MetallicRoughnessMaterial
      const hex: string = color.replace('#', '').slice(-6)
      const rgb: number = /^[0-9a-fA-F]{6}$/.test(hex) ? parseInt(hex, 16) : 0x5be3b0
      const r: number = this.linearColor((rgb >> 16) & 255)
      const g: number = this.linearColor((rgb >> 8) & 255)
      const b: number = this.linearColor(rgb & 255)
      material.baseColor.factor = { x: r, y: g, z: b, w: 1 }
      material.material.factor = { x: 0, y: 0.38, z: 0.08, w: 0.5 }
      material.emissive.factor = { x: r * 0.07, y: g * 0.07, z: b * 0.07, w: 1 }
      const pending: Node[] = [view.node]
      while (pending.length > 0) {
        const current: Node = pending.pop()!
        if (current.nodeType === NodeType.GEOMETRY) (current as Geometry).mesh.materialOverride = material
        for (let index: number = 0; index < current.children.count(); index++) {
          const child: Node | null = current.children.get(index)
          if (child !== null) pending.push(child)
        }
      }
      this.requestRender()
    } catch (error) {
      if (generation === this.graphGeneration) console.warn('[GalaxyNative] material failed: ' + this.errorMessage(error))
    }
  }

  private linearColor = (value: number): number => {
    const channel: number = value / 255
    return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  private applySceneTransforms(): void {
    for (const view of this.nodeViews) {
      view.node.position = rotateGalaxyPoint({ x: view.baseX, y: view.baseY, z: view.baseZ }, this.rotationAngle, this.pitchAngle)
    }
    this.positionEdges()
    this.updateLabels()
    this.requestRender()
  }

  private positionEdges(): void {
    for (const view of this.edgeViews) {
      const source: NativeNodeView | null = this.findNodeView(view.edge.fromId)
      const target: NativeNodeView | null = this.findNodeView(view.edge.toId)
      if (source === null || target === null) {
        view.node.visible = false
        continue
      }
      view.node.visible = this.selectedId === view.edge.fromId || this.selectedId === view.edge.toId
      const dx: number = target.node.position.x - source.node.position.x
      const dy: number = target.node.position.y - source.node.position.y
      const dz: number = target.node.position.z - source.node.position.z
      const length: number = Math.max(0.1, Math.sqrt(dx * dx + dy * dy + dz * dz))
      const selected: boolean = this.selectedId === view.edge.fromId || this.selectedId === view.edge.toId
      const width: number = selected ? 0.18 : 0.07
      view.node.position = {
        x: (source.node.position.x + target.node.position.x) / 2,
        y: (source.node.position.y + target.node.position.y) / 2,
        z: (source.node.position.z + target.node.position.z) / 2,
      }
      view.node.rotation = galaxyEdgeRotation({ x: dx, y: dy, z: dz })
      view.node.scale = { x: length, y: width, z: width }
    }
  }

  private applySelection(): void {
    for (const view of this.nodeViews) {
      const graphNode: GalaxyGraphNode | null = this.findGraphNode(view.id)
      const baseScale: number = graphNode === null ? 0.8 : 0.7 + graphNode.mastery * 0.45
      const scale: number = view.id === this.selectedId ? baseScale * 1.4 : baseScale
      view.node.scale = { x: scale, y: scale, z: scale }
    }
    this.positionEdges()
    this.updateLabels()
    this.requestRender()
  }

  private updateCameraDistance(): void {
    if (this.camera !== null) {
      this.camera.position = { x: 0, y: 0, z: this.cameraDistance }
      this.camera.rotation = { x: 0, y: 0, z: 0, w: 1 }
      this.camera.fov = 0.84
      this.updateLabels()
      this.requestRender()
    }
  }

  private handleTap(event: GestureEvent): void {
    if (this.camera === null || this.paused || event.fingerList.length === 0) {
      return
    }
    const width: number = Math.max(1, this.viewportWidth)
    const height: number = Math.max(1, this.viewportHeight)
    const position: Vec2 = galaxyRaycastPosition(event.fingerList[0].localX, event.fingerList[0].localY, width, height)
    const generation: number = this.graphGeneration
    this.camera.raycast(position, {}).then((hits: RaycastResult[]): void => {
      if (generation !== this.graphGeneration || this.paused || this.camera === null) return
      if (hits.length === 0) {
        this.callbacks.onClearSelection()
        return
      }
      let id: string = ''
      // Native Node.path may name the parent path. Use the unique imported node
      // name and walk Geometry parents; skip stars/edges rather than masking hits.
      for (const hit of hits) {
        let current: Node | null = hit.node
        while (current !== null && id.length === 0) {
          id = this.nodePathToId.get(current.name) ?? ''
          current = current.parent
        }
        if (id.length > 0) break
      }
      if (id.length > 0) {
        this.callbacks.onSelect(id)
      } else {
        this.callbacks.onClearSelection()
      }
    }).catch((error: Error): void => {
      if (generation !== this.graphGeneration || this.paused || this.camera === null) return
      this.callbacks.onFailure('native_raycast_failed: ' + error.message)
    })
  }

  private updateLabels(): void {
    if (this.camera === null) return
    const labels: NativeLabelView[] = []
    const width: number = Math.max(1, this.viewportWidth)
    const height: number = Math.max(1, this.viewportHeight)
    for (const view of this.nodeViews) {
      const graphNode: GalaxyGraphNode | null = this.findGraphNode(view.id)
      if (graphNode === null) {
        continue
      }
      const point: Vec2 | null = projectGalaxyPoint(view.node.position, this.camera.getViewMatrix(),
        this.camera.getProjectionMatrix(), width, height)
      const previous: NativeLabelView | undefined = this.labels.find((label: NativeLabelView): boolean => label.id === view.id)
      const label: NativeLabelView = previous ?? new NativeLabelView(view.id, graphNode.label, 0, 0)
      label.visible = point !== null
      if (point !== null) {
        if (Math.abs(label.x - point.x) > 0.2) label.x = point.x
        if (Math.abs(label.y - point.y) > 0.2) label.y = point.y
      }
      label.label = graphNode.label
      labels.push(label)
    }
    const changed: boolean = labels.length !== this.labels.length || labels.some((label: NativeLabelView, index: number): boolean => {
      const previous: NativeLabelView = this.labels[index]
      return previous.id !== label.id
    })
    if (changed) this.labels = labels
  }

  private requestRender(): void {
    if (!this.paused && this.scene !== null) {
      this.scene.renderFrame({ alwaysRender: false })
      // Camera matrices are updated by the native render thread, not by setters.
      // Refresh a short burst after a change rather than leaving labels one frame behind.
      this.labelFramesRemaining = 6
      if (this.labelTimer < 0) {
        this.labelTimer = setInterval((): void => {
          if (this.paused || this.scene === null || this.labelFramesRemaining-- <= 0) {
            this.stopLabelRefresh()
            return
          }
          this.updateLabels()
        }, 33)
      }
    }
  }

  private onSnapshotChanged(): void {
    this.rebuildGraph()
  }

  private onSelectionChanged(): void {
    this.applySelection()
  }

  private onPausedChanged(): void {
    if (!this.paused) {
      this.resume()
    } else {
      this.pause()
    }
  }

  private stopLabelRefresh = (): void => {
    if (this.labelTimer >= 0) clearInterval(this.labelTimer)
    this.labelTimer = -1
    this.labelFramesRemaining = 0
  }

  private onViewportChanged = (): void => {
    this.updateLabels()
    this.requestRender()
  }

  private findNode(scene: Scene, path: string): Node | null {
    return findGalaxyTemplate(scene, path)
  }

  private findNodeView(id: string): NativeNodeView | null {
    for (const view of this.nodeViews) {
      if (view.id === id) {
        return view
      }
    }
    return null
  }

  private findGraphNode(id: string): GalaxyGraphNode | null {
    for (const node of this.snapshot.nodes) {
      if (node.id === id) {
        return node
      }
    }
    return null
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }

  private errorMessage(error: Object): string {
    return (error as Error).message ?? String(error)
  }
}
