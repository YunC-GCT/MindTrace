import abilityTest from './Ability.test';
import chatPersistenceCapabilityDeviceTest from './ChatPersistenceCapabilityDevice.test';
import entryTests from '../../../test/List.test';
// Prepare with: node scripts/prepare-knowledge-hypium.mjs
import agentsTests from '../generated-knowledge-tests/agents/List.test';
import commonTests from '../generated-knowledge-tests/common/List.test';

export default function testsuite() {
  abilityTest();
  chatPersistenceCapabilityDeviceTest();
  // NoteTools includes the cold-store gate: run before entry's real RDB context fixture.
  commonTests();
  agentsTests();
  entryTests();
}
