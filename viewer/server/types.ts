export type ToneName =
  | "neutral"
  | "green"
  | "teal"
  | "pink"
  | "lime"
  | "orange"
  | "violet"
  | "amber";

export type IndexEntry =
  | {
      kind: "adr";
      id: string;
      number: string;
      title: string;
      status: string;
      path: string;
      last_modified: string;
    }
  | {
      kind: "project";
      slug: string;
      name: string;
      tone: ToneName;
      flat_path: string;
    };
