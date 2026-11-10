// The kanban contrib's slice of the fake Scooter: one board, "Work", with the
// "old" conversation in Design and "pinned" in Review. Moves refile through
// PUT /conversations/<id>/folder, as the real agent-host does.
const STAGES = [
  { id: "s1", label: "Design", position: 0 },
  { id: "s2", label: "Review", position: 1 },
];
const placements = { old: "s1", pinned: "s2" };
const cards = {
  old: { column: "s1", position: 0, note: "KANBAN-NOTE", updated_by: "agent", updated_at: new Date().toISOString() },
};

export const kanbanMoves = [];

export async function kanbanRoutes({ method, path, body }) {
  if (method === "GET" && path === "/contrib-api/kanban/boards")
    return { json: { boards: [{ folder: "b1", stages: STAGES, tags: [], skills: [] }] } };
  if (method === "GET" && path === "/folders")
    return {
      json: {
        folders: [{ id: "b1", name: "Work", kind: "user", locked: true }, ...STAGES.map((s) => ({ id: s.id, name: s.label, kind: "user", parentId: "b1" }))],
        placements,
      },
    };
  if (method === "POST" && path === "/contrib-api/kanban/boards/b1/cards") {
    const { conversations } = await body();
    return { json: { cards: Object.fromEntries(conversations.map((id) => [id, { card: cards[id] ?? null, blockers: [], tags: [], priority: "none" }])) } };
  }
  const folder = path.match(/^\/conversations\/([^/]+)\/folder$/);
  if (method === "PUT" && folder) {
    placements[folder[1]] = (await body()).folderId;
    return { json: { ok: true } };
  }
  const card = path.match(/^\/conversations\/([^/]+)\/contrib-api\/kanban\/card$/);
  if (method === "PUT" && card) {
    const { column, position } = await body();
    cards[card[1]] = { ...cards[card[1]], column, position, updated_by: "user", updated_at: new Date().toISOString() };
    kanbanMoves.push([card[1], column]);
    return { json: { card: cards[card[1]] } };
  }
  return undefined;
}
