/**
 * NoteGenerationRepositoryFactory.ets — composition root for generation artifacts.
 * It reuses DatabaseHelper's sole RDB store and does not create a note DAO.
 */
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import { NoteGenerationRepository } from '../database/NoteGenerationRepository';
import { NoteDao } from '../database/NoteDao';

export class NoteGenerationRepositoryFactory {
  static async create(context: common.UIAbilityContext): Promise<NoteGenerationRepository> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    return new NoteGenerationRepository(store, new NoteDao(store));
  }
}
