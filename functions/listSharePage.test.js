const test = require("node:test");
const assert = require("node:assert/strict");

const {
  questionPreviewsForListShare,
  renderListSharePage,
} = require("./listSharePage");

test("list share previews include up to three current shareable questions", async () => {
  const db = createFakeDb({
    "questions/q1": {
      source: "seeded",
      localizedTexts: { tr: "Birinci soru?" },
      category: "Daily",
    },
    "questions/q2": {
      source: "userCreated",
      moderationStatus: "approved",
      text: "Second question?",
      category: "Friends",
    },
    "questions/q3": {
      source: "userCreated",
      moderationStatus: "rejected",
      text: "Rejected question?",
      category: "Hidden",
    },
    "questions/q4": {
      source: "seeded",
      text: "Fourth question?",
      category: "Life",
    },
    "questions/q5": {
      source: "seeded",
      text: "Fifth question?",
      category: "Work",
    },
  });

  const result = await questionPreviewsForListShare(db, ["q1", "q2", "q3", "q4", "q5"], 3);

  assert.deepEqual(result.previews, [
    { id: "q1", text: "Birinci soru?", category: "Daily" },
    { id: "q2", text: "Second question?", category: "Friends" },
    { id: "q4", text: "Fourth question?", category: "Life" },
  ]);
  assert.equal(result.overflowCount, 2);
});

test("list share page renders previews, overflow, canonical URL, and asset path", () => {
  const html = renderListSharePage({
    title: "Friends - TTB",
    description: "A shared list",
    listName: "Friends",
    ownerDisplayName: "@berke",
    questionCount: 4,
    includesAnswers: true,
    shareUrl: "https://ttbp-9d652.web.app/share/lists/code",
    appUrl: "ttbp://l/code",
    questionPreviews: [
      { text: "Question one?", category: "Daily" },
      { text: "Question two?", category: "Work" },
      { text: "Question three?", category: "Friends" },
    ],
    overflowCount: 1,
  });

  assert.match(html, /<link rel="canonical" href="https:\/\/ttbp-9d652\.web\.app\/share\/lists\/code">/);
  assert.match(html, /\/assets\/launch-logo\.png/);
  assert.match(html, /Question one\?/);
  assert.match(html, /\+1 soru daha/);
  assert.match(html, /TestFlight ile yukle/);
  assert.doesNotMatch(html, /answerSnapshots|ownerAnswerSnapshots|latestReplyAnswerSnapshots/);
});

function createFakeDb(initialDocuments) {
  const documents = new Map(
    Object.entries(initialDocuments).map(([path, data]) => [path, structuredClone(data)])
  );

  return {
    collection(path) {
      return {
        doc(id) {
          return {
            async get() {
              return createSnapshot(id, `${path}/${id}`, documents.get(`${path}/${id}`));
            },
          };
        },
      };
    },
  };
}

function createSnapshot(id, path, data) {
  return {
    id,
    path,
    exists: data !== undefined,
    data() {
      return data === undefined ? undefined : structuredClone(data);
    },
  };
}
