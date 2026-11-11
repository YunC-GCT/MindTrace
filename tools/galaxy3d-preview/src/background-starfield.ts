interface StarLife {
  age: number;
  fadeIn: number;
  hold: number;
  fadeOut: number;
  rest: number;
  peak: number;
  velocityX: number;
  velocityY: number;
  velocityZ: number;
}

/**
 * One bounded WebGL pool, no screen-fixed DOM overlay or knowledge identities.
 * Each independent life totals 1–10s: 30% fade in, 20% hold, 30% fade out,
 * 20% hidden, then choose a new position and timing while hidden.
 * Independent drift is twice the original speed; no camera spin.
 * Initial phases are staggered. Only foreground seconds advance the pool.
 */
export class BackgroundStarfield {
  readonly opacities: Float32Array;
  readonly positions: Float32Array;
  private readonly stars: StarLife[];
  private readonly random: () => number;

  constructor(count: number, random: () => number = Math.random) {
    this.random = random;
    this.opacities = new Float32Array(count);
    this.positions = new Float32Array(count * 3);
    this.stars = Array.from({ length: count }, () => this.newLife());
    for (let index = 0; index < count; index += 1) {
      const star = this.stars[index];
      star.age = random() * (star.fadeIn + star.hold + star.fadeOut + star.rest);
      this.opacities[index] = opacityAt(star);
      this.place(index);
    }
  }

  advance(seconds: number, paused = false, motionScale = 1): void {
    if (paused || !Number.isFinite(seconds) || seconds <= 0) return;
    for (let index = 0; index < this.stars.length; index += 1) {
      const star = this.stars[index];
      star.age += seconds;
      if (star.age >= star.fadeIn + star.hold + star.fadeOut + star.rest) {
        this.stars[index] = this.newLife();
        this.place(index);
        this.opacities[index] = 0;
      } else {
        const drift = seconds * Math.max(0, Math.min(1, motionScale));
        this.positions[index * 3] += star.velocityX * drift;
        this.positions[index * 3 + 1] += star.velocityY * drift;
        this.positions[index * 3 + 2] += star.velocityZ * drift;
        this.opacities[index] = opacityAt(star);
      }
    }
  }

  private newLife(): StarLife {
    const lifetime = 1 + this.random() * 9;
    return {
      age: 0, fadeIn: lifetime * 0.3, hold: lifetime * 0.2,
      fadeOut: lifetime * 0.3, rest: lifetime * 0.2,
      peak: 0.5 + this.random() * 0.5,
      velocityX: 2 * (0.35 + this.random() * 0.4),
      velocityY: 2 * (0.15 + this.random() * 0.2),
      velocityZ: 2 * (this.random() - 0.5) * 0.2,
    };
  }

  private place(index: number): void {
    // Outside the knowledge/camera volume: stars never sweep across a nearby sphere.
    const radius = 160 + this.random() * 100;
    const theta = this.random() * Math.PI * 2;
    const z = this.random() * 2 - 1;
    const plane = Math.sqrt(1 - z * z);
    this.positions[index * 3] = radius * plane * Math.cos(theta);
    this.positions[index * 3 + 1] = radius * plane * Math.sin(theta);
    this.positions[index * 3 + 2] = radius * z;
  }
}

function opacityAt(star: StarLife): number {
  if (star.age < star.fadeIn) return star.peak * smooth(star.age / star.fadeIn);
  const fadeStart = star.fadeIn + star.hold;
  if (star.age < fadeStart) return star.peak;
  if (star.age < fadeStart + star.fadeOut) {
    return star.peak * (1 - smooth((star.age - fadeStart) / star.fadeOut));
  }
  return 0;
}

function smooth(value: number): number {
  return value * value * (3 - 2 * value);
}
