export const ValidMetaDataKey = ['protocol'] as const;
export type MetaDataKey = (typeof ValidMetaDataKey)[number];
