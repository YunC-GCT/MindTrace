/** Decorative star layers; compositor animation stays available in low GPU quality mode. */
export function createDomStarfield(container: HTMLElement): void {
  const palette = ['#d9f4ff', '#5be3b0', '#f6c56d'];
  const layers = ['far', 'middle', 'near'].map((depth) => {
    const layer = document.createElement('div');
    layer.className = `galaxy-star-plane galaxy-star-plane--${depth}`;
    container.appendChild(layer);
    return layer;
  });

  for (let index = 0; index < 180; index += 1) {
    const star = document.createElement('i');
    const depth = index % layers.length;
    const size = 0.8 + depth * 0.4 + seededNoise(index + 41.7) * 1.4;
    star.className = 'galaxy-star';
    star.style.left = `${seededNoise(index * 2.3 + 3.1) * 100}%`;
    star.style.top = `${seededNoise(index * 4.7 + 9.4) * 100}%`;
    star.style.width = `${size}px`;
    star.style.height = `${size}px`;
    // Offset the palette from depth so each plane contains all three colors.
    star.style.color = palette[Math.floor(index / layers.length) % palette.length];
    star.style.backgroundColor = 'currentColor';
    star.style.opacity = `${0.24 + seededNoise(index + 17.2) * 0.58}`;
    layers[depth].appendChild(star);
  }
}

function seededNoise(value: number): number {
  const raw = Math.sin(value * 12.9898 + 78.233) * 43758.5453;
  return raw - Math.floor(raw);
}
