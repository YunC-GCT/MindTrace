/**
 * GalaxyModels.ets — 知识星系的可视化数据形状
 *
 * 路径: common/src/main/ets/models/GalaxyModels.ets
 * 职责: 定义星系渲染前的学科系、章节轨道、星球与连线数据结构；不含布局算法
 * 依赖: ./CommonTypes (KnowledgeUnit), ../data/MockNotes (NoteItem)
 *
 * 数据流:
 *   KnowledgeGalaxyViewModel → 本文件模型 → GalaxyGraphProjection → 3D / Web 渲染
 */
import { KnowledgeUnit } from './CommonTypes';
import { NoteItem } from '../data/MockNotes';

export type GalaxyLinkType = 'prerequisite' | 'related';

export class GalaxyLink {
  fromId: string = '';
  toId: string = '';
  type: GalaxyLinkType = 'related';
  fromChapter: string = '';
  toChapter: string = '';

  constructor(
    fromId: string,
    toId: string,
    type: GalaxyLinkType,
    fromChapter: string,
    toChapter: string,
  ) {
    this.fromId = fromId;
    this.toId = toId;
    this.type = type;
    this.fromChapter = fromChapter;
    this.toChapter = toChapter;
  }
}

export class PlanetNode {
  id: string = '';
  note: NoteItem = new NoteItem(0, '', '', '', '', 0, '', [], '');
  unit: KnowledgeUnit | null = null;
  subject: string = '';
  chapter: string = '';
  type: string = '';
  color: string = '';
  angle: number = 0;
  speed: number = 0;
  size: number = 0;
  mastery: number = 0;
  alpha: number = 1;

  constructor(
    id: string,
    note: NoteItem,
    unit: KnowledgeUnit,
    subject: string,
    chapter: string,
    type: string,
    color: string,
    angle: number,
    speed: number,
    size: number,
    mastery: number,
    alpha: number,
  ) {
    this.id = id;
    this.note = note;
    this.unit = unit;
    this.subject = subject;
    this.chapter = chapter;
    this.type = type;
    this.color = color;
    this.angle = angle;
    this.speed = speed;
    this.size = size;
    this.mastery = mastery;
    this.alpha = alpha;
  }
}

export class ChapterOrbit {
  chapter: string = '';
  count: number = 0;
  mastery: number = 0;
  radiusX: number = 0;
  radiusY: number = 0;
  tilt: number = 0;
  labelX: number = 0;
  labelY: number = 0;
  planets: PlanetNode[] = [];

  constructor(
    chapter: string,
    count: number,
    mastery: number,
    radiusX: number,
    radiusY: number,
    tilt: number,
    labelX: number,
    labelY: number,
    planets: PlanetNode[],
  ) {
    this.chapter = chapter;
    this.count = count;
    this.mastery = mastery;
    this.radiusX = radiusX;
    this.radiusY = radiusY;
    this.tilt = tilt;
    this.labelX = labelX;
    this.labelY = labelY;
    this.planets = planets;
  }
}

export class SubjectSystem {
  subject: string = '';
  color: string = '';
  count: number = 0;
  mastery: number = 0;
  x: number = 0;
  y: number = 0;
  size: number = 0;
  planets: PlanetNode[] = [];
  orbits: ChapterOrbit[] = [];
  links: GalaxyLink[] = [];

  constructor(
    subject: string,
    color: string,
    count: number,
    mastery: number,
    x: number,
    y: number,
    size: number,
    planets: PlanetNode[],
    orbits: ChapterOrbit[],
    links: GalaxyLink[],
  ) {
    this.subject = subject;
    this.color = color;
    this.count = count;
    this.mastery = mastery;
    this.x = x;
    this.y = y;
    this.size = size;
    this.planets = planets;
    this.orbits = orbits;
    this.links = links;
  }
}
