// ============================================================================
//  pages/Review/GalaxyGraphProjection.ets - pure 3D galaxy data projection
//  ----------------------------------------------------------------------------
//  Converts Review domain nodes into renderer DTOs. No ArkUI or renderer state.
// ============================================================================

import type { GalaxyLink, PlanetNode, SubjectSystem } from '../../viewmodels/KnowledgeGalaxyViewModel'

const WRONG_NOTE_TYPE: string = '错题'

export type GalaxyGraphEdgeType = 'prerequisite' | 'related'

export interface GalaxyGraphNode {
  id: string
  label: string
  subject: string
  chapter: string
  mastery: number
  color: string
}

export interface GalaxyGraphEdge {
  id: string
  fromId: string
  toId: string
  type: GalaxyGraphEdgeType
}

export interface GalaxyGraphSnapshot {
  nodes: GalaxyGraphNode[]
  edges: GalaxyGraphEdge[]
}

function isRenderablePlanet(planet: PlanetNode): boolean {
  const id: string = planet.id.trim()
  return id.length > 0
    && planet.type.trim() !== WRONG_NOTE_TYPE
    && planet.note.type.trim() !== WRONG_NOTE_TYPE
}

function nodeLabel(planet: PlanetNode): string {
  const title: string = planet.note.title.trim()
  if (title.length > 0) {
    return title
  }
  const type: string = planet.type.trim()
  return type.length > 0 ? type : '笔记'
}

function toGraphNode(planet: PlanetNode): GalaxyGraphNode {
  return {
    id: planet.id.trim(),
    label: nodeLabel(planet),
    subject: planet.subject,
    chapter: planet.chapter,
    mastery: Math.max(0, Math.min(1, planet.mastery)),
    color: planet.color,
  }
}

function toGraphEdge(link: GalaxyLink, nodeIds: string[]): GalaxyGraphEdge | null {
  const sourceId: string = link.fromId.trim()
  const targetId: string = link.toId.trim()
  if (sourceId.length === 0 || targetId.length === 0 || sourceId === targetId) {
    return null
  }
  if (nodeIds.indexOf(sourceId) < 0 || nodeIds.indexOf(targetId) < 0) {
    return null
  }
  if (link.type === 'prerequisite') {
    return {
      id: 'prerequisite:' + sourceId + '->' + targetId,
      fromId: sourceId,
      toId: targetId,
      type: 'prerequisite',
    }
  }
  if (link.type === 'related') {
    const fromId: string = sourceId < targetId ? sourceId : targetId
    const toId: string = sourceId < targetId ? targetId : sourceId
    return {
      id: 'related:' + fromId + '<->' + toId,
      fromId: fromId,
      toId: toId,
      type: 'related',
    }
  }
  return null
}

export function projectGalaxyGraph(systems: SubjectSystem[]): GalaxyGraphSnapshot {
  const nodes: GalaxyGraphNode[] = []
  const nodeIds: string[] = []
  const edges: GalaxyGraphEdge[] = []
  const edgeIds: string[] = []

  for (const system of systems) {
    for (const planet of system.planets) {
      if (!isRenderablePlanet(planet)) {
        continue
      }
      const id: string = planet.id.trim()
      if (nodeIds.indexOf(id) >= 0) {
        continue
      }
      nodeIds.push(id)
      nodes.push(toGraphNode(planet))
    }
  }

  for (const system of systems) {
    for (const link of system.links) {
      const edge: GalaxyGraphEdge | null = toGraphEdge(link, nodeIds)
      if (edge === null || edgeIds.indexOf(edge.id) >= 0) {
        continue
      }
      edgeIds.push(edge.id)
      edges.push(edge)
    }
  }

  return { nodes: nodes, edges: edges }
}
