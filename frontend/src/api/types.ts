import type { components } from './schema';

type Schemas = components['schemas'];

export type Session = Schemas['SessionOut'];
export type SessionState = Schemas['SessionState'];
export type SessionSort = Schemas['SessionSort'];
export type SessionCreate = Schemas['SessionCreate'];
export type SessionPatch = Schemas['SessionPatch'];
export type Job = Schemas['JobOut'];
export type JobState = Schemas['JobState'];
export type SearchResult = Schemas['SearchResultOut'];
export type Artist = Schemas['ArtistOut'];
export type LiveEvent = Schemas['LiveEvent'];
export type Stem = Schemas['Stem'];
export type StemMix = Schemas['StemMix'];
export type MixState = Schemas['MixStateOut'];
export type MixStateIn = Schemas['MixStateIn'];
export type MixPreset = Schemas['MixPreset'];
export type Export = Schemas['ExportOut'];
export type ExportFormat = Schemas['ExportFormat'];
export type ExportState = Schemas['ExportState'];

/** `GET /peaks/{stem}.json` (o OpenAPI não tipa: é um arquivo servido como está). */
export interface StemPeaks {
  duration_s: number;
  peaks: number[];
}

/** O Pydantic gera `counts` como `{[key: string]: number}`; aqui ele é tipado pelos estados. */
export type SessionCounts = Record<SessionState, number>;

export interface SessionList {
  items: Session[];
  total: number;
  counts: SessionCounts;
}

export interface SessionListParams {
  q?: string;
  state?: SessionState[];
  sort?: SessionSort;
  limit?: number;
  offset?: number;
}
