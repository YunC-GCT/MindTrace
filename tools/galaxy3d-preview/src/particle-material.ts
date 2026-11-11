/** Web-only materials: analytic alpha avoids device-dependent canvas textures. */
import * as THREE from 'three';

export function createKnowledgeMaterial(color: THREE.ColorRepresentation): THREE.MeshPhysicalMaterial {
  return new THREE.MeshPhysicalMaterial({
    color, roughness: 0.4, metalness: 0.1, fog: false,
    clearcoat: 0.12, clearcoatRoughness: 0.38, specularIntensity: 0.25,
    emissive: color, emissiveIntensity: 0,
    transparent: false, depthWrite: true,
  });
}

export function createStarMaterial(): THREE.PointsMaterial {
  const material = new THREE.PointsMaterial({
    color: 0xffffff, size: 2.2, transparent: true, opacity: 0.65,
    depthWrite: false, sizeAttenuation: false, fog: false, toneMapped: false,
  });
  material.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float starOpacity;\nvarying float vStarOpacity;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvStarOpacity = starOpacity;');
    shader.fragmentShader = shader.fragmentShader.replace('#include <common>',
      '#include <common>\nvarying float vStarOpacity;');
    shader.fragmentShader = shader.fragmentShader.replace('#include <color_fragment>', `
      #include <color_fragment>
      float radius = length(gl_PointCoord - vec2(0.5));
      if (radius >= 0.5) discard;
      diffuseColor.a *= vStarOpacity * (1.0 - smoothstep(0.12, 0.5, radius));
    `);
  };
  material.customProgramCacheKey = () => 'white-lifecycle-stars-v2';
  return material;
}

export function createGlowMaterial(color: THREE.ColorRepresentation): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: { tint: { value: new THREE.Color(color) }, strength: { value: 0 } },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `
      varying vec3 surfaceNormal;
      varying vec3 viewDirection;
      void main() {
        vec4 viewPosition = modelViewMatrix * vec4(position, 1.0);
        surfaceNormal = normalize(normalMatrix * normal);
        viewDirection = -viewPosition.xyz;
        gl_Position = projectionMatrix * viewPosition;
      }
    `,
    fragmentShader: `
      uniform vec3 tint;
      uniform float strength;
      varying vec3 surfaceNormal;
      varying vec3 viewDirection;
      void main() {
        float facing = max(dot(normalize(surfaceNormal), normalize(viewDirection)), 0.0);
        gl_FragColor = vec4(tint, strength * pow(facing, 3.0));
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
}
