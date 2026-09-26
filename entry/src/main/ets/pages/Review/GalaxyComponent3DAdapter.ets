// ============================================================================
//  pages/Review/GalaxyComponent3DAdapter.ets - native Component3D renderer
// ============================================================================

import {
  Camera,
  Node,
  RaycastResult,
  Scene,
} from '@kit.ArkGraphics3D'
import { TEXT, TEXT_2, BG_CARD, BORDER, R_MD, S_2 } from 'common'
import { AppIcon } from '../../shared/atoms/AppIcon'
import type { GalaxyGraphEdge, GalaxyGraphNode, GalaxyGraphSnapshot } from './GalaxyGraphProjection'
import {
  GalaxyNoopCallbacks,
  GalaxyPerformanceSample,
  GalaxyRendererCallbacks,
} from './GalaxyRendererContracts'

const CAMERA_DEFAULT_DISTANCE: number = 72
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

class NativeLabelView {
  id: string = ''
  label: string = ''
  x: number = 0
  y: number = 0

  constructor(id: string, label: string, x: number, y: number) {
    this.id = id
    this.label = label
    this.x = x
    this.y = y
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
  @State private scene: Scene | null = null
  @State private labels: NativeLabelView[] = []
  private camera: Camera | null = null
  private nodeViews: NativeNodeView[] = []
  private edgeViews: NativeEdgeView[] = []
  private nodePathToId: Map<string, string> = new Map<string, string>()
  private rotationAngle: number = 0
  private panStartAngle: number = 0
  private cameraDistance: number = CAMERA_DEFAULT_DISTANCE
  private pinchStartDistance: number = CAMERA_DEFAULT_DISTANCE
  private loadGeneration: number = 0

  aboutToAppear(): void {
    this.loadScene()
  }

  aboutToDisappear(): void {
    this.release()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.scene !== null) {
        Component3D({ scene: this.scene })
          .width('100%')
          .height('100%')
          .gesture(
            GestureGroup(
              GestureMode.Parallel,
              PanGesture({ direction: PanDirection.All })
                .onActionStart((): void => {
                  this.panStartAngle = this.rotationAngle
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.rotationAngle = this.panStartAngle + event.offsetX * 0.006
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
            Text(label.label)
              .fontSize(11)
              .fontColor(label.id === this.selectedId ? TEXT : TEXT_2)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .width(104)
              .padding({ left: 5, right: 5, top: 3, bottom: 3 })
              .backgroundColor('#C010131A')
              .border({ width: 0.5, color: BORDER })
              .borderRadius(R_MD)
              .position({ x: label.x - 52, y: label.y - 28 })
              .accessibilityText(label.label)
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
    this.cameraDistance = CAMERA_DEFAULT_DISTANCE
    this.applySceneTransforms()
    this.updateCameraDistance()
  }

  pause(): void {}

  resume(): void {
    this.requestRender()
  }

  release(): void {
    this.loadGeneration++
    this.clearGraphNodes()
    if (this.scene !== null) {
      try { this.scene.destroy() } catch (_error) {}
    }
    this.scene = null
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
        loaded.destroy()
        this.callbacks.onFailure('native_scene_templates_missing')
        return
      }
      this.scene = loaded
      this.camera = cameraNode as Camera
      this.camera.enabled = true
      nodeTemplate.visible = false
      prerequisiteTemplate.visible = false
      relatedTemplate.visible = false
      this.rebuildGraph()
      this.callbacks.onReady()
      this.callbacks.onPerformance(new GalaxyPerformanceSample('native', 0, 0, false))
    } catch (error) {
      this.callbacks.onFailure('native_scene_load_failed: ' + this.errorMessage(error))
    }
  }

  private rebuildGraph(): void {
    if (this.scene === null || this.scene.root === null) {
      return
    }
    const nodeTemplate: Node | null = this.findNode(this.scene, NODE_TEMPLATE_PATH)
    const prerequisiteTemplate: Node | null = this.findNode(this.scene, PREREQUISITE_TEMPLATE_PATH)
    const relatedTemplate: Node | null = this.findNode(this.scene, RELATED_TEMPLATE_PATH)
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
      sceneNode.visible = true
      const scale: number = 0.7 + graphNode.mastery * 0.45
      sceneNode.scale = { x: scale, y: scale, z: scale }
      this.nodeViews.push(new NativeNodeView(graphNode.id, sceneNode, x, y, z))
      this.nodePathToId.set(sceneNode.path, graphNode.id)
      index++
    }
    index = 0
    for (const edge of this.snapshot.edges) {
      const template: Node = edge.type === 'prerequisite' ? prerequisiteTemplate : relatedTemplate
      const edgeNode: Node = this.scene.importNode('GalaxyEdge_' + index.toString(), template, this.scene.root)
      edgeNode.visible = true
      this.edgeViews.push(new NativeEdgeView(edge, edgeNode))
      index++
    }
    this.applySceneTransforms()
    this.applySelection()
  }

  private clearGraphNodes(): void {
    for (const view of this.nodeViews) {
      try { view.node.destroy() } catch (_error) {}
    }
    for (const view of this.edgeViews) {
      try { view.node.destroy() } catch (_error) {}
    }
    this.nodeViews = []
    this.edgeViews = []
    this.nodePathToId.clear()
  }

  private applySceneTransforms(): void {
    for (const view of this.nodeViews) {
      const positionX: number = view.baseX * Math.cos(this.rotationAngle) - view.baseY * Math.sin(this.rotationAngle)
      const positionY: number = view.baseX * Math.sin(this.rotationAngle) + view.baseY * Math.cos(this.rotationAngle)
      view.node.position = { x: positionX, y: positionY, z: view.baseZ }
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
      view.node.visible = true
      const dx: number = target.node.position.x - source.node.position.x
      const dy: number = target.node.position.y - source.node.position.y
      const dz: number = target.node.position.z - source.node.position.z
      const length: number = Math.max(0.1, Math.sqrt(dx * dx + dy * dy + dz * dz))
      const angle: number = Math.atan2(dy, dx)
      const selected: boolean = this.selectedId === view.edge.fromId || this.selectedId === view.edge.toId
      const width: number = selected ? 0.18 : 0.07
      view.node.position = {
        x: (source.node.position.x + target.node.position.x) / 2,
        y: (source.node.position.y + target.node.position.y) / 2,
        z: (source.node.position.z + target.node.position.z) / 2,
      }
      view.node.rotation = { x: 0, y: 0, z: Math.sin(angle / 2), w: Math.cos(angle / 2) }
      view.node.scale = { x: length / 1.7, y: width, z: width }
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
      this.requestRender()
    }
  }

  private handleTap(event: GestureEvent): void {
    if (this.camera === null || event.fingerList.length === 0) {
      return
    }
    const width: number = Math.max(1, this.viewportWidth)
    const height: number = Math.max(1, this.viewportHeight)
    const x: number = event.fingerList[0].localX / width * 2 - 1
    const y: number = 1 - event.fingerList[0].localY / height * 2
    this.camera.raycast({ x: x, y: y }, {}).then((hits: RaycastResult[]): void => {
      if (hits.length === 0) {
        this.callbacks.onClearSelection()
        return
      }
      const id: string = this.nodePathToId.get(hits[0].node.path) ?? ''
      if (id.length > 0) {
        this.callbacks.onSelect(id)
      } else {
        this.callbacks.onClearSelection()
      }
    }).catch((error: Error): void => {
      this.callbacks.onFailure('native_raycast_failed: ' + error.message)
    })
  }

  private updateLabels(): void {
    const labels: NativeLabelView[] = []
    const width: number = Math.max(1, this.viewportWidth)
    const height: number = Math.max(1, this.viewportHeight)
    for (const view of this.nodeViews) {
      const graphNode: GalaxyGraphNode | null = this.findGraphNode(view.id)
      if (graphNode === null) {
        continue
      }
      const x: number = width / 2 + view.node.position.x / this.cameraDistance * width * 0.9
      const y: number = height / 2 - view.node.position.y / this.cameraDistance * height * 0.9
      labels.push(new NativeLabelView(view.id, graphNode.label, x, y))
    }
    this.labels = labels
  }

  private requestRender(): void {
    if (!this.paused && this.scene !== null) {
      this.scene.renderFrame({ alwaysRender: false })
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
    }
  }

  private findNode(scene: Scene, path: string): Node | null {
    return scene.getNodeByPath(path) ?? scene.getNodeByPath('/' + path)
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
