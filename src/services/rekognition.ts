import {
  CreateCollectionCommand,
  DeleteFacesCommand,
  IndexFacesCommand,
  RekognitionClient,
  SearchFacesByImageCommand,
} from '@aws-sdk/client-rekognition';
import { config } from '../config.js';
import { query } from '../db.js';
import { badRequest } from '../lib/errors.js';

let client: RekognitionClient | null = null;

function rekognition(): RekognitionClient {
  if (!client) {
    client = new RekognitionClient({
      region: config.awsRegion,
      // The default provider chain uses the hermes secret-store environment
      // (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) or an instance role.
    });
  }
  return client;
}

export function collectionIdFor(orgId: string): string {
  return `${config.rekognitionCollectionPrefix}-${orgId}`;
}

function errorName(error: unknown): string {
  return (error as { name?: string }).name ?? '';
}

export async function ensureCollection(orgId: string): Promise<string> {
  const collectionId = collectionIdFor(orgId);
  try {
    await rekognition().send(new CreateCollectionCommand({ CollectionId: collectionId }));
  } catch (error) {
    if (errorName(error) !== 'ResourceAlreadyExistsException') throw error;
  }
  return collectionId;
}

export interface IndexedFace {
  faceId: string;
  imageId: string | null;
  quality: Record<string, unknown>;
}

async function deleteFacesFromCollection(
  collectionId: string,
  faceIds: string[],
): Promise<void> {
  for (let index = 0; index < faceIds.length; index += 1000) {
    const chunk = faceIds.slice(index, index + 1000);
    if (!chunk.length) continue;
    try {
      await rekognition().send(
        new DeleteFacesCommand({ CollectionId: collectionId, FaceIds: chunk }),
      );
    } catch (error) {
      if (errorName(error) !== 'ResourceNotFoundException') throw error;
    }
  }
}

export async function listEmployeeFaces(
  orgId: string,
  employeeId: string,
): Promise<Array<{ faceId: string; createdAt: string; quality: Record<string, unknown> }>> {
  const rows = await query<{ face_id: string; created_at: string; quality: Record<string, unknown> }>(
    `SELECT face_id, created_at, quality
     FROM employee_faces
     WHERE org_id = $1 AND employee_id = $2
     ORDER BY created_at ASC`,
    [orgId, employeeId],
  );
  return rows.map((row) => ({
    faceId: row.face_id,
    createdAt: row.created_at,
    quality: row.quality ?? {},
  }));
}

/**
 * Index one or more face images for an employee. The collection is created on
 * first use. Images are not stored; Rekognition keeps only its face vectors.
 */
export async function indexEmployeeFaces(
  orgId: string,
  employeeId: string,
  images: Buffer[],
): Promise<IndexedFace[]> {
  if (!images.length) throw badRequest('At least one face image is required.');
  if (images.length > 10) throw badRequest('Use at most ten face images.');
  const collectionId = await ensureCollection(orgId);

  const indexed: IndexedFace[] = [];
  try {
    for (const [offset, image] of images.entries()) {
      const result = await rekognition().send(
        new IndexFacesCommand({
          CollectionId: collectionId,
          Image: { Bytes: image },
          ExternalImageId: employeeId,
          MaxFaces: 1,
          QualityFilter: 'AUTO',
          DetectionAttributes: [],
        }),
      );
      const record = result.FaceRecords?.[0];
      const faceId = record?.Face?.FaceId;
      if (!faceId) {
        throw badRequest(`No usable face was detected in image ${offset + 1}.`);
      }
      indexed.push({
        faceId,
        imageId: record?.Face?.ImageId ?? null,
        quality: (record?.FaceDetail?.Quality ?? {}) as Record<string, unknown>,
      });
    }

    for (const face of indexed) {
      await query(
        `INSERT INTO employee_faces
          (org_id, employee_id, collection_id, face_id, image_id, external_image_id, quality)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (collection_id, face_id) DO NOTHING`,
        [
          orgId,
          employeeId,
          collectionId,
          face.faceId,
          face.imageId,
          employeeId,
          JSON.stringify(face.quality),
        ],
      );
    }
    return indexed;
  } catch (error) {
    // Do not leave untracked faces in the collection if one sample failed.
    await deleteFacesFromCollection(collectionId, indexed.map((face) => face.faceId)).catch(
      () => undefined,
    );
    throw error;
  }
}

/**
 * Replace an employee's enrolled faces. New faces are indexed first, then the
 * previous faces are removed so a failed re-enrollment does not delete the old
 * enrollment.
 */
export async function replaceEmployeeFaces(
  orgId: string,
  employeeId: string,
  images: Buffer[],
): Promise<IndexedFace[]> {
  const collectionId = collectionIdFor(orgId);
  const previous = await query<{ face_id: string }>(
    'SELECT face_id FROM employee_faces WHERE org_id = $1 AND employee_id = $2',
    [orgId, employeeId],
  );
  const previousIds = previous.map((row) => row.face_id);
  const indexed = await indexEmployeeFaces(orgId, employeeId, images);

  if (previousIds.length) {
    await deleteFacesFromCollection(collectionId, previousIds);
    await query(
      `DELETE FROM employee_faces
       WHERE org_id = $1 AND employee_id = $2 AND NOT (face_id = ANY($3::text[]))`,
      [orgId, employeeId, indexed.map((face) => face.faceId)],
    );
  }
  return indexed;
}

export async function clearEmployeeFaces(orgId: string, employeeId: string): Promise<void> {
  const collectionId = collectionIdFor(orgId);
  const rows = await query<{ face_id: string }>(
    'SELECT face_id FROM employee_faces WHERE org_id = $1 AND employee_id = $2',
    [orgId, employeeId],
  );
  await deleteFacesFromCollection(collectionId, rows.map((row) => row.face_id));
  await query('DELETE FROM employee_faces WHERE org_id = $1 AND employee_id = $2', [
    orgId,
    employeeId,
  ]);
}

export interface FaceMatch {
  employeeId: string;
  similarity: number;
  faceId: string;
  ambiguous: boolean;
}

/**
 * Pick the best distinct-employee match. Exposed for deterministic tests.
 * A second distinct employee within the ambiguity margin is treated as
 * ambiguous instead of silently choosing one person.
 */
export function selectFaceMatch(
  matches: Array<{ employeeId: string; similarity: number; faceId: string }>,
  threshold: number,
  ambiguityMargin: number,
): FaceMatch | null {
  const ranked = matches
    .filter((match) => match.employeeId && match.faceId)
    .sort((a, b) => b.similarity - a.similarity);
  if (!ranked.length) return null;
  const top = ranked[0]!;
  if (top.similarity < threshold) return null;
  const second = ranked.find((match) => match.employeeId !== top.employeeId);
  const ambiguous = Boolean(
    second && top.similarity - second.similarity < ambiguityMargin,
  );
  return {
    employeeId: top.employeeId,
    similarity: top.similarity,
    faceId: top.faceId,
    ambiguous,
  };
}

/**
 * Search the org's collection. Returns null when no face clears the configured
 * similarity threshold.
 */
export async function searchEmployeeFace(
  orgId: string,
  image: Buffer,
): Promise<FaceMatch | null> {
  const collectionId = collectionIdFor(orgId);
  let result;
  try {
    result = await rekognition().send(
      new SearchFacesByImageCommand({
        CollectionId: collectionId,
        Image: { Bytes: image },
        MaxFaces: 5,
        FaceMatchThreshold: config.rekognitionSimilarityThreshold,
      }),
    );
  } catch (error) {
    if (errorName(error) === 'ResourceNotFoundException') return null;
    throw error;
  }

  const matches = (result.FaceMatches ?? []).map((match) => ({
    employeeId: match.Face?.ExternalImageId ?? '',
    similarity: Number(match.Similarity ?? 0),
    faceId: match.Face?.FaceId ?? '',
  }));

  return selectFaceMatch(
    matches,
    config.rekognitionSimilarityThreshold,
    config.rekognitionAmbiguityMargin,
  );
}
