// #238 契约层：ArtifactStorePort 契约测试。
// 装载真实 entry 适配器源码；文件与清单用内存假 IO，覆盖幂等、冲突与部分失败回滚。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

class NotePortError extends Error {
  constructor(code, message, retryable) {
    super(message);
    this.name = 'NotePortError';
    this.code = code;
    this.retryable = retryable;
  }
}

const mod = loadNoteReviewEtsModule(
  'entry/src/main/ets/database/ArtifactStoreAdapter.ets',
  { mocks: { common: { NotePortError } } },
);
const ArtifactStoreAdapter = mod.ArtifactStoreAdapter;

function memoryIo() {
  const files = new Map();
  const io = {
    files,
    failNextWriteText: false,
    failNextWriteBytes: false,
    failNextRemove: false,
    failReadText: false,
    readBytes: async (path) => files.get(path) ?? null,
    writeBytes: async (path, bytes) => {
      if (io.failNextWriteBytes) { io.failNextWriteBytes = false; throw new Error('write failed'); }
      files.set(path, bytes);
    },
    readText: async (path) => {
      if (io.failReadText) { throw new Error('io read failed'); }
      return files.get(path) ?? null;
    },
    writeText: async (path, text) => {
      if (io.failNextWriteText) { io.failNextWriteText = false; throw new Error('disk full'); }
      files.set(path, text);
    },
    remove: async (path) => {
      if (io.failNextRemove) { io.failNextRemove = false; throw new Error('delete failed'); }
      return files.delete(path);
    },
    exists: async (path) => files.has(path),
  };
  return io;
}

const bytesOf = (text) => new TextEncoder().encode(text);

test('ArtifactStore.put writes bytes plus manifest and returns a descriptor', async () => {
  const io = memoryIo();
  const store = new ArtifactStoreAdapter('/root', io);
  const descriptor = await store.put('img-1', 'image/png', bytesOf('png-bytes'));
  assert.equal(descriptor.artifactId, 'img-1');
  assert.equal(descriptor.mediaType, 'image/png');
  assert.equal(descriptor.size, 9);
  assert.equal(descriptor.duplicate, false);
  assert.match(descriptor.checksum, /^[0-9a-f]{8}$/);
  assert.equal(io.files.has('/root/img-1.bin'), true);
  assert.equal(io.files.has('/root/artifacts-manifest.json'), true);
});

test('ArtifactStore.put is idempotent for the same id and bytes', async () => {
  const io = memoryIo();
  const store = new ArtifactStoreAdapter('/root', io);
  const first = await store.put('img-1', 'image/png', bytesOf('same'));
  const replay = await store.put('img-1', 'image/png', bytesOf('same'));
  assert.equal(replay.duplicate, true);
  assert.equal(replay.checksum, first.checksum);
  assert.equal(replay.createdAt, first.createdAt, 'replay must return the first descriptor');
  const manifest = JSON.parse(io.files.get('/root/artifacts-manifest.json'));
  assert.equal(manifest.items.length, 1, 'replay must not append a second manifest entry');
});

test('ArtifactStore.put rejects the same id with different bytes as a non-retryable conflict', async () => {
  const io = memoryIo();
  const store = new ArtifactStoreAdapter('/root', io);
  await store.put('img-1', 'image/png', bytesOf('first'));
  await assert.rejects(store.put('img-1', 'image/png', bytesOf('second')), (error) => {
    assert.equal(error.code, 'ARTIFACT_CONFLICT');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('ArtifactStore.put rejects an empty artifactId', async () => {
  const store = new ArtifactStoreAdapter('/root', memoryIo());
  await assert.rejects(store.put('', 'image/png', bytesOf('x')), (error) => {
    assert.equal(error.code, 'INVALID_ARTIFACT_ID');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('ArtifactStore.put rejects ids that could escape the root directory', async () => {
  const store = new ArtifactStoreAdapter('/root', memoryIo());
  for (const id of ['../evil', 'a/b', '..', 'a\\b']) {
    await assert.rejects(store.put(id, 'image/png', bytesOf('x')), (error) => error.code === 'INVALID_ARTIFACT_ID');
  }
});

test('ArtifactStore.put wraps byte-write failures into ARTIFACT_WRITE_FAILED (retryable)', async () => {
  const io = memoryIo();
  io.failNextWriteBytes = true;
  const store = new ArtifactStoreAdapter('/root', io);
  await assert.rejects(store.put('img-1', 'image/png', bytesOf('abc')), (error) => {
    assert.equal(error.code, 'ARTIFACT_WRITE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});

test('ArtifactStore.get returns the descriptor and null when absent', async () => {
  const store = new ArtifactStoreAdapter('/root', memoryIo());
  await store.put('img-1', 'image/png', bytesOf('abc'));
  const found = await store.get('img-1');
  assert.equal(found.artifactId, 'img-1');
  assert.equal(found.duplicate, false);
  assert.equal(await store.get('missing'), null);
});

test('ArtifactStore.remove deletes the artifact and reports missing ids as false', async () => {
  const io = memoryIo();
  const store = new ArtifactStoreAdapter('/root', io);
  await store.put('img-1', 'image/png', bytesOf('abc'));
  assert.equal(await store.remove('img-1'), true);
  assert.equal(await store.get('img-1'), null);
  assert.equal(io.files.has('/root/img-1.bin'), false);
  assert.equal(await store.remove('img-1'), false);
});

test('ArtifactStore.remove keeps descriptor and file consistent when the file delete fails', async () => {
  const io = memoryIo();
  const store = new ArtifactStoreAdapter('/root', io);
  await store.put('img-1', 'image/png', bytesOf('abc'));
  io.failNextRemove = true;
  await assert.rejects(store.remove('img-1'), (error) => {
    assert.equal(error.code, 'ARTIFACT_DELETE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
  const still = await store.get('img-1');
  assert.equal(still.artifactId, 'img-1', 'manifest must be restored when the file delete fails');
  assert.equal(io.files.has('/root/img-1.bin'), true, 'the file must survive a failed remove');
});

test('ArtifactStore.put rolls back the written file when the manifest write fails', async () => {
  const io = memoryIo();
  io.failNextWriteText = true;
  const store = new ArtifactStoreAdapter('/root', io);
  await assert.rejects(store.put('img-1', 'image/png', bytesOf('abc')), (error) => {
    assert.equal(error.code, 'ARTIFACT_WRITE_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
  assert.equal(io.files.has('/root/img-1.bin'), false, 'partial write must be cleaned up');
});

test('ArtifactStore.get surfaces manifest read failures as ARTIFACT_READ_FAILED', async () => {
  const io = memoryIo();
  io.failReadText = true;
  const store = new ArtifactStoreAdapter('/root', io);
  await assert.rejects(store.get('img-1'), (error) => {
    assert.equal(error.code, 'ARTIFACT_READ_FAILED');
    assert.equal(error.retryable, true);
    return true;
  });
});
