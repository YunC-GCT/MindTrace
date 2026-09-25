// ============================================================================
//  pages/Review/GalaxyWebAdapter.ets - ArkWeb/Three.js galaxy renderer
// ============================================================================

import { webview } from '@kit.ArkWeb'
import type { GalaxyGraphSnapshot } from './GalaxyGraphProjection'
import {
  GalaxyNoopCallbacks,
  GalaxyPerformanceSample,
  GalaxyRendererCallbacks,
} from './GalaxyRendererContracts'

const GALAXY_PORT_TOKEN: string = '__GALAXY_PORT__'
const WEB_READY_TIMEOUT_MS: number = 5000

class GalaxyWebPayload {
  snapshot?: GalaxyGraphSnapshot
  selectedId?: string | null
  paused?: boolean
  id?: string
  reason?: string
  fps?: number
  particles?: number
  degraded?: boolean
}

class GalaxyWebMessage {
  version: number = 1
  type: string = ''
  payload: GalaxyWebPayload = new GalaxyWebPayload()
}

@Component
export struct GalaxyWebAdapter {
  @Prop @Watch('onSnapshotChanged') snapshot: GalaxyGraphSnapshot = { nodes: [], edges: [] }
  @Prop @Watch('onSelectionChanged') selectedId: string = ''
  @Prop @Watch('onPausedChanged') paused: boolean = false
  callbacks: GalaxyRendererCallbacks = new GalaxyNoopCallbacks()
  private controller: webview.WebviewController = new webview.WebviewController()
  private port: webview.WebMessagePort | null = null
  private ready: boolean = false
  private readyTimer: number = -1

  aboutToAppear(): void {
    this.readyTimer = setTimeout((): void => {
      if (!this.ready) {
        this.callbacks.onFailure('web_renderer_ready_timeout')
      }
    }, WEB_READY_TIMEOUT_MS)
  }

  aboutToDisappear(): void {
    this.release()
  }

  build() {
    Web({ src: $rawfile('galaxy3d/index.html'), controller: this.controller })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .fileAccess(true)
      .zoomAccess(false)
      .backgroundColor('#FF0A0C10')
      .onPageEnd((): void => {
        this.createMessageChannel()
        this.sendInitialGraph()
      })
      .onErrorReceive((event: OnErrorReceiveEvent): void => {
        this.callbacks.onFailure(
          'web_resource_load_failed: code=' + event.error.getErrorCode().toString()
            + ' main=' + event.request.isMainFrame().toString()
            + ' url=' + event.request.getRequestUrl()
            + ' info=' + event.error.getErrorInfo(),
        )
      })
      .onRenderExited((): void => this.callbacks.onFailure('web_render_process_exited'))
  }

  setSnapshot(snapshot: GalaxyGraphSnapshot): void {
    this.snapshot = snapshot
    this.sendInitialGraph()
  }

  setSelection(id: string): void {
    this.selectedId = id
    const payload: GalaxyWebPayload = new GalaxyWebPayload()
    payload.selectedId = id.length > 0 ? id : null
    this.postToWeb('set_selection', payload)
  }

  resetCamera(): void {
    this.postToWeb('reset_camera', new GalaxyWebPayload())
  }

  pause(): void {
    const payload: GalaxyWebPayload = new GalaxyWebPayload()
    payload.paused = true
    this.postToWeb('set_paused', payload)
  }

  resume(): void {
    const payload: GalaxyWebPayload = new GalaxyWebPayload()
    payload.paused = false
    this.postToWeb('set_paused', payload)
  }

  release(): void {
    if (this.readyTimer !== -1) {
      clearTimeout(this.readyTimer)
      this.readyTimer = -1
    }
    if (this.port !== null) {
      try { this.port.close() } catch (_error) {}
      this.port = null
    }
    this.ready = false
  }

  private onSnapshotChanged(): void {
    this.sendInitialGraph()
  }

  private onSelectionChanged(): void {
    const payload: GalaxyWebPayload = new GalaxyWebPayload()
    payload.selectedId = this.selectedId.length > 0 ? this.selectedId : null
    this.postToWeb('set_selection', payload)
  }

  private onPausedChanged(): void {
    if (this.paused) {
      this.pause()
    } else {
      this.resume()
    }
  }

  private createMessageChannel(): void {
    try {
      if (this.port !== null) {
        this.port.close()
        this.port = null
      }
      const ports: webview.WebMessagePort[] = this.controller.createWebMessagePorts()
      this.port = ports[1]
      this.port.onMessageEvent((message: webview.WebMessage): void => {
        this.handleWebMessage(message)
      })
      this.controller.postMessage(GALAXY_PORT_TOKEN, [ports[0]], '*')
    } catch (error) {
      this.callbacks.onFailure('web_message_channel_failed: ' + this.errorMessage(error))
    }
  }

  private sendInitialGraph(): void {
    const payload: GalaxyWebPayload = new GalaxyWebPayload()
    payload.snapshot = this.snapshot
    payload.selectedId = this.selectedId.length > 0 ? this.selectedId : null
    this.postToWeb('init_graph', payload)
  }

  private postToWeb(type: string, payload: GalaxyWebPayload): void {
    if (this.port === null) {
      return
    }
    const message: GalaxyWebMessage = new GalaxyWebMessage()
    message.type = type
    message.payload = payload
    this.port.postMessageEvent(JSON.stringify(message))
  }

  private handleWebMessage(raw: webview.WebMessage): void {
    const message: GalaxyWebMessage | null = this.parseMessage(raw)
    if (message === null) {
      return
    }
    if (message.type === 'scene_ready') {
      this.ready = true
      if (this.readyTimer !== -1) {
        clearTimeout(this.readyTimer)
        this.readyTimer = -1
      }
      this.callbacks.onReady()
      this.sendInitialGraph()
    } else if (message.type === 'scene_failure') {
      this.callbacks.onFailure(message.payload.reason ?? 'web_scene_failed')
    } else if (message.type === 'node_selected') {
      const id: string = message.payload.id ?? ''
      if (id.length > 0) {
        this.callbacks.onSelect(id)
      }
    } else if (message.type === 'selection_cleared') {
      this.callbacks.onClearSelection()
    } else if (message.type === 'perf_sample') {
      this.callbacks.onPerformance(new GalaxyPerformanceSample(
        'web',
        message.payload.fps ?? 0,
        message.payload.particles ?? 0,
        message.payload.degraded ?? false,
      ))
    }
  }

  private parseMessage(raw: webview.WebMessage): GalaxyWebMessage | null {
    try {
      const text: string = typeof raw === 'string' ? raw : String(raw)
      const message: GalaxyWebMessage = JSON.parse(text) as GalaxyWebMessage
      if (message.version !== 1 || message.type.length === 0) {
        return null
      }
      return message
    } catch (_error) {
      return null
    }
  }

  private errorMessage(error: Object): string {
    return (error as Error).message ?? String(error)
  }
}
